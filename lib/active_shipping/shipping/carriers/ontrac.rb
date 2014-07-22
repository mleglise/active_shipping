# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class OnTrac < Carrier
      self.retry_safe = true

      cattr_accessor :default_options
      cattr_reader :name
      @@name = "OnTrac"

      TEST_URL = 'https://www.shipontrac.net/OnTracTestWebServices/OnTracServices.svc/V1'
      LIVE_URL = 'https://www.shipontrac.net/OnTracWebServices/OnTracServices.svc/V1'

      RESOURCES = {
        :rates => 'rates',
        :track => 'shipments'
      }

      EVENT_CODES = HashWithIndifferentAccess.new({
        "AI" => "Delivery address incomplete",
        "AN" => "Delivery area not accessible",
        "BW" => "Delay in delivery due to bad weather",
        "CA" => "Change of delivery address",
        "CK" => "COD check collected from consignee",
        "CL" => "Delivered in good condition",
        "CO" => "Company closed on delivery attempt",
        "CR" => "Recipient refused delivery",
        "DC" => "Package received damaged",
        "DD" => "Package delivered damaged",
        "DG" => "Unsendable - Dangerous Goods",
        "DI" => "Change in delivery date requested",
        "DM" => "Delivered open - contents may be missing",
        "DN" => "Delivered to neighbor",
        "DR" => "Refused to accept damaged package",
        "ER" => "Incorrect status code enterred",
        "HO" => "Recipient closed for holiday",
        "HP" => "Held for customer pickup",
        "HW" => "Held in warehouse",
        "IP" => "Unsendable - Improper Packaging",
        "MC" => "Contact OnTrac Customer Service 1-800-334-5000",
        "NH" => "Not home on delivery attempt",
        "OD" => "Out for Delivery",
        "OE" => "Data entry",
        "OK" => "Delivered in good condition",
        "OO" => "Data entry",
        "OS" => "Package received at facility",
        "PU" => "Picked up from shipper",
        "RB" => "Redeliver on next business day",
        "RD" => "Package received at facility",
        "RS" => "Return to sender on next business day",
        "UA" => "Unsendable - Incomplete Delivery Address",
        "UC" => "Unsendable - Unacceptable contents / value",
        "UD" => "Unsendable - Badly Damaged",
        "UM" => "Undeliverable - Missorted",
        "UN" => "Undeliverable - Other reasons",
        "UO" => "Unsendable - Other reasons",
        "WA" => "Wrong delivery address",
        "WD" => "Delivered to wrong address and retrieved",
        "XX" => "Data entry"
      })

      TRACKING_STATUS_CODES = HashWithIndifferentAccess.new({
        "AI" => :exception,
        "AN" => :exception,
        "BW" => :exception,
        "CA" => :exception,
        "CK" => :in_transit,
        "CL" => :delivered,
        "CO" => :exception,
        "CR" => :exception,
        "DC" => :exception,
        "DD" => :delivered,
        "DG" => :exception,
        "DI" => :in_transit,
        "DM" => :delivered,
        "DN" => :delivered,
        "DR" => :exception,
        "ER" => :exception,
        "HO" => :in_transit,
        "HP" => :exception,
        "HW" => :exception,
        "IP" => :exception,
        "MC" => :exception,
        "NH" => :in_transit,
        "OD" => :out_for_delivery,
        "OE" => :pickup,
        "OK" => :delivered,
        "OO" => :pickup,
        "OS" => :in_transit,
        "PU" => :in_transit,
        "RB" => :in_transit,
        "RD" => :in_transit,
        "RS" => :in_transit,
        "UA" => :exception,
        "UC" => :exception,
        "UD" => :exception,
        "UM" => :exception,
        "UN" => :exception,
        "UO" => :exception,
        "WA" => :exception,
        "WD" => :exception,
        "XX" => :pickup
      })

      DEFAULT_SERVICES = HashWithIndifferentAccess.new({
        "S" => "Sunrise",
        "G" => "Gold",
        "H" => "Palletized Freight",
        "C" => "OnTrac Ground"
      })

      LABEL_TYPES = HashWithIndifferentAccess.new({
        "0" => "No label",
        "1" => "PDF",
        "2" => "JPG",
        "3" => "BMP",
        "4" => "GIF",
        "6" => "4x5 EPL label",
        "7" => "4x5 ZPL"
      })

      ONTRAC_DELIVERY_STATES = ["CA", "WA", "OR", "CO", "AZ", "NV", "UT", "ID"]

      def requirements
        [:account, :password]
      end

      def find_rates(origin, destination, packages, options={})
        raise NotImplemented
        options = @options.merge(options)
        packages = Array(packages)
        rate_request = build_rate_request(origin, destination, packages, options)
        response = commit(:rates, save_request(rate_request), (options[:test] || false))
        parse_rate_response(origin, destination, packages, response, options)
      end

      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)
        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(:track, save_request(tracking_request), (options[:test] || false))
        parse_tracking_response(response, options)
      end

      protected

      def build_rate_request(origin, destination, packages, options={})
        raise NotImplemented
        packages = Array(packages)
        xml_request = XmlNode.new('RatingServiceSelectionRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Rate')
            request << XmlNode.new('RequestOption', 'Shop')
            # not implemented: 'Rate' RequestOption to specify a single service query
            # request << XmlNode.new('RequestOption', ((options[:service].nil? or options[:service] == :all) ? 'Shop' : 'Rate'))
          end

          pickup_type = options[:pickup_type] || :daily_pickup

          root_node << XmlNode.new('PickupType') do |pickup_type_node|
            pickup_type_node << XmlNode.new('Code', PICKUP_CODES[pickup_type])
            # not implemented: PickupType/PickupDetails element
          end
          cc = options[:customer_classification] || DEFAULT_CUSTOMER_CLASSIFICATIONS[pickup_type]
          root_node << XmlNode.new('CustomerClassification') do |cc_node|
            cc_node << XmlNode.new('Code', CUSTOMER_CLASSIFICATIONS[cc])
          end

          root_node << XmlNode.new('Shipment') do |shipment|
            # not implemented: Shipment/Description element
            shipment << build_location_node('Shipper', (options[:shipper] || origin), options)
            shipment << build_location_node('ShipTo', destination, options)
            if options[:shipper] and options[:shipper] != origin
              shipment << build_location_node('ShipFrom', origin, options)
            end

            # not implemented:  * Shipment/ShipmentWeight element
            #                   * Shipment/ReferenceNumber element
            #                   * Shipment/Service element
            #                   * Shipment/PickupDate element
            #                   * Shipment/ScheduledDeliveryDate element
            #                   * Shipment/ScheduledDeliveryTime element
            #                   * Shipment/AlternateDeliveryTime element
            #                   * Shipment/DocumentsOnly element

            packages.each do |package|
              imperial = ['US','LR','MM'].include?(origin.country_code(:alpha2))

              shipment << XmlNode.new("Package") do |package_node|

                # not implemented:  * Shipment/Package/PackagingType element
                #                   * Shipment/Package/Description element

                package_node << XmlNode.new("PackagingType") do |packaging_type|
                  packaging_type << XmlNode.new("Code", '02')
                end

                package_node << XmlNode.new("Dimensions") do |dimensions|
                  dimensions << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'IN' : 'CM')
                  end
                  [:length,:width,:height].each do |axis|
                    value = ((imperial ? package.inches(axis) : package.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
                    dimensions << XmlNode.new(axis.to_s.capitalize, [value,0.1].max)
                  end
                end

                package_node << XmlNode.new("PackageWeight") do |package_weight|
                  package_weight << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
                  end

                  value = ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
                  package_weight << XmlNode.new("Weight", [value,0.1].max)
                end

                # not implemented:  * Shipment/Package/LargePackageIndicator element
                #                   * Shipment/Package/ReferenceNumber element
                #                   * Shipment/Package/PackageServiceOptions element
                #                   * Shipment/Package/AdditionalHandling element
              end

            end

            # not implemented:  * Shipment/ShipmentServiceOptions element
            if options[:origin_account]
              shipment << XmlNode.new("RateInformation") do |rate_info_node|
                rate_info_node << XmlNode.new("NegotiatedRatesIndicator")
              end
            end
          end
        end
        xml_request.to_s
      end

      def build_tracking_request(tracking_number, options={})
        "requestType=track&tn=#{tracking_number}"
      end

      def build_location_node(name,location,options={})
        raise NotImplemented
        # not implemented:  * Shipment/Shipper/Name element
        #                   * Shipment/(ShipTo|ShipFrom)/CompanyName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/AttentionName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/TaxIdentificationNumber element
        location_node = XmlNode.new(name) do |location_node|
          location_node << XmlNode.new('PhoneNumber', location.phone.gsub(/[^\d]/,'')) unless location.phone.blank?
          location_node << XmlNode.new('FaxNumber', location.fax.gsub(/[^\d]/,'')) unless location.fax.blank?

          if name == 'Shipper' and (origin_account = @options[:origin_account] || options[:origin_account])
            location_node << XmlNode.new('ShipperNumber', origin_account)
          elsif name == 'ShipTo' and (destination_account = @options[:destination_account] || options[:destination_account])
            location_node << XmlNode.new('ShipperAssignedIdentificationNumber', destination_account)
          end

          location_node << XmlNode.new('Address') do |address|
            address << XmlNode.new("AddressLine1", location.address1) unless location.address1.blank?
            address << XmlNode.new("AddressLine2", location.address2) unless location.address2.blank?
            address << XmlNode.new("AddressLine3", location.address3) unless location.address3.blank?
            address << XmlNode.new("City", location.city) unless location.city.blank?
            address << XmlNode.new("StateProvinceCode", location.province) unless location.province.blank?
              # StateProvinceCode required for negotiated rates but not otherwise, for some reason
            address << XmlNode.new("PostalCode", location.postal_code) unless location.postal_code.blank?
            address << XmlNode.new("CountryCode", location.country_code(:alpha2)) unless location.country_code(:alpha2).blank?
            address << XmlNode.new("ResidentialAddressIndicator", true) unless location.commercial? # the default should be that UPS returns residential rates for destinations that it doesn't know about
            # not implemented: Shipment/(Shipper|ShipTo|ShipFrom)/Address/ResidentialAddressIndicator element
          end
        end
      end

      def parse_rate_response(origin, destination, packages, response, options={})
        raise NotImplemented
        rates = []

        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          rate_estimates = []

          xml.elements.each('/*/RatedShipment') do |rated_shipment|
            service_code = rated_shipment.get_text('Service/Code').to_s
            days_to_delivery = rated_shipment.get_text('GuaranteedDaysToDelivery').to_s.to_i
            days_to_delivery = nil if days_to_delivery == 0

            rate_estimates << RateEstimate.new(origin, destination, @@name,
                                service_name_for(origin, service_code),
                                :total_price => rated_shipment.get_text('TotalCharges/MonetaryValue').to_s.to_f,
                                :currency => rated_shipment.get_text('TotalCharges/CurrencyCode').to_s,
                                :service_code => service_code,
                                :packages => packages,
                                :delivery_range => [timestamp_from_business_day(days_to_delivery)],
                                :negotiated_rate =>                               rated_shipment.get_text('NegotiatedRates/NetSummaryCharges/GrandTotal/MonetaryValue').to_s.to_f)
          end
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
      end

      def parse_tracking_response(response, options={})
        xml = REXML::Document.new(response).elements[1]
        success = response_success?(xml)
        message = response_message(xml)

        if success
          tracking_number, origin, destination, status_code, status_description = nil
          delivered, exception = false
          exception_event = nil
          shipment_events = []
          status = {}
          scheduled_delivery_date = nil

          first_shipment = xml.elements['/*/Shipments/Shipment']
          tracking_number = first_shipment.get_text('Tracking').to_s
          destination = location_from_address_node(first_shipment)

          # Parse the tracking events
          activities = first_shipment.get_elements('Events/Event')
          unless activities.empty?
            shipment_events = activities.map do |activity|
              description = activity.get_text('Description').to_s
              zoneless_time = Time.parse(activity.get_text('EventTime').to_s)
              location = location_from_address_node(activity)
              ShipmentEvent.new(description, zoneless_time, location)
            end

            shipment_events = shipment_events.sort_by(&:time)

            # Build status hash
            status_code = activities.first.get_text('Status').to_s
            status_description = EVENT_CODES[status_code]
            status = TRACKING_STATUS_CODES[status_code]
          end

          # Get scheduled delivery date
          unless status == :delivered
            scheduled_delivery_date = Time.parse(first_shipment.get_text('Exp_Del_Date').to_s)
          end

        end
        TrackingResponse.new(success, message, Hash.from_xml(response).values.first,
          :carrier => @@name,
          :xml => response,
          :request => last_request,
          :status => status,
          :status_code => status_code,
          :status_description => status_description,
          :scheduled_delivery_date => scheduled_delivery_date,
          :shipment_events => shipment_events,
          :delivered => delivered,
          :exception => exception,
          :exception_event => exception_event,
          :origin => origin,
          :destination => destination,
          :tracking_number => tracking_number)
      end

      def location_from_address_node(address)
        return nil unless address
        # Catch the "Corporate" facility, suppress the location.
        # This is to prevent customer confusion.
        # Only used when head office makes a note.
        facility = node_text_or_nil(address.elements['Facility'])
        if facility and node_text_or_nil(address.elements['Facility']).strip == "Corporate"
          Location.new(
            :name => 'Note from Corporate Office'
          )
        else
          # Default
          Location.new(
            :country =>     'US',
            :postal_code => node_text_or_nil(address.elements['Zip']),
            :province =>    node_text_or_nil(address.elements['State']),
            :city =>        node_text_or_nil(address.elements['City']),
            :address1 =>    node_text_or_nil(address.elements['Addr1']),
            :address2 =>    node_text_or_nil(address.elements['Addr2']),
            :address3 =>    node_text_or_nil(address.elements['Addr3']),
            :name =>        node_text_or_nil(address.elements['Name'])
          )
        end
      end

      def response_success?(xml)
        xml.elements['/*/Shipments/Shipment'] != nil
      end

      def response_message(xml)
        if !xml.get_text('/*/Error').to_s.blank?
          xml.get_text('/*/Error').to_s
        else
          xml.get_text('/*/Note').to_s
        end
      end

      def commit(action, request, test = false)
        ssl_get(request_url(action, request, test))
      end
      
      def request_url(action, request, test)
        root_url = test ? TEST_URL : LIVE_URL
        "#{root_url}/#{@options[:account]}/#{RESOURCES[action]}?pw=#{@options[:password]}&#{request}"
      end


      def service_name_for(origin, code)
        name = DEFAULT_SERVICES[code]
      end

    end
  end
end
