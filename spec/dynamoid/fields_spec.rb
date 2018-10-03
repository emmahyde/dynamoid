# frozen_string_literal: true

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Dynamoid::Fields do
  let(:address) { Address.new }

  it 'declares read attributes' do
    expect(address.city).to be_nil
  end

  it 'declares write attributes' do
    address.city = 'Chicago'
    expect(address.city).to eq 'Chicago'
  end

  it 'declares a query attribute' do
  end

  it 'automatically declares id' do
    expect { address.id }.to_not raise_error
  end

  it 'allows range key serializers' do
    date_serializer = Class.new do
      def self.dump(val)
        val&.strftime('%m/%d/%Y')
      end

      def self.load(val)
        val && DateTime.strptime(val, '%m/%d/%Y')
      end
    end

    expect do
      model = Class.new do
        include Dynamoid::Document
        table name: :special
        range :special_date, :serialized, serializer: date_serializer
      end
    end.to_not raise_error
  end

  it 'automatically declares and fills in created_at and updated_at' do
    address.save

    address.reload
    expect(address.created_at).to be_a DateTime
    expect(address.updated_at).to be_a DateTime
  end

  context 'query attributes' do
    it 'are declared' do
      expect(address.city?).to be_falsey

      address.city = 'Chicago'

      expect(address.city?).to be_truthy
    end

    it 'return false when boolean attributes are nil or false' do
      address.deliverable = nil
      expect(address.deliverable?).to be_falsey

      address.deliverable = false
      expect(address.deliverable?).to be_falsey
    end

    it 'return true when boolean attributes are true' do
      address.deliverable = true
      expect(address.deliverable?).to be_truthy
    end
  end

  context 'with a saved address' do
    let(:address) { Address.create(deliverable: true) }
    let(:original_id) { address.id }

    it 'should write an attribute correctly' do
      address.write_attribute(:city, 'Chicago')
    end

    it 'should write an attribute with an alias' do
      address[:city] = 'Chicago'
    end

    it 'should read a written attribute' do
      address.write_attribute(:city, 'Chicago')
      expect(address.read_attribute(:city)).to eq 'Chicago'
    end

    it 'should read a written attribute with the alias' do
      address.write_attribute(:city, 'Chicago')
      expect(address[:city]).to eq 'Chicago'
    end

    it 'should update one attribute' do
      expect(address).to receive(:save).once.and_return(true)
      address.update_attribute(:city, 'Chicago')
      expect(address[:city]).to eq 'Chicago'
      expect(address.id).to eq original_id
    end

    it 'adds in dirty methods for attributes' do
      address.city = 'Chicago'
      address.save

      address.city = 'San Francisco'

      expect(address.city_was).to eq 'Chicago'
    end

    it 'returns all attributes' do
      expect(Address.attributes).to eq(id: { type: :string },
                                       created_at: { type: :datetime },
                                       updated_at: { type: :datetime },
                                       city: { type: :string },
                                       options: { type: :serialized },
                                       deliverable: { type: :boolean },
                                       latitude: { type: :number },
                                       config: { type: :raw },
                                       registered_on: { type: :date },
                                       lock_version: { type: :integer })
    end
  end

  it 'raises an exception when items size exceeds 400kb' do
    expect do
      Address.create(city: 'Ten chars ' * 500_000)
    end.to raise_error(Aws::DynamoDB::Errors::ValidationException, 'Item size has exceeded the maximum allowed size')
  end

  context '.remove_attribute' do
    subject { address }
    before(:each) do
      Address.field :foobar
      Address.remove_field :foobar
    end

    it 'should not be in the attributes hash' do
      expect(Address.attributes).to_not have_key(:foobar)
    end

    it 'removes the accessor' do
      expect(subject).to_not respond_to(:foobar)
    end

    it 'removes the writer' do
      expect(subject).to_not respond_to(:foobar=)
    end

    it 'removes the interrogative' do
      expect(subject).to_not respond_to(:foobar?)
    end
  end

  context 'default values for fields' do
    let(:doc_class) do
      Class.new do
        include Dynamoid::Document

        field :name, :string, default: 'x'
        field :uid, :integer, default: -> { 42 }
        field :config, :serialized, default: {}
        field :version, :integer, default: 1
        field :hidden, :boolean, default: false

        def self.name
          'Document'
        end
      end
    end

    it 'returns default value specified as object' do
      expect(doc_class.new.name).to eq('x')
    end

    it 'returns default value specified as lamda/block (callable object)' do
      expect(doc_class.new.uid).to eq(42)
    end

    it 'returns default value as is for serializable field' do
      expect(doc_class.new.config).to eq({})
    end

    it 'supports `false` as default value' do
      expect(doc_class.new.hidden).to eq(false)
    end

    it 'can modify default value independently for every instance' do
      doc = doc_class.new
      doc.name << 'y'
      expect(doc_class.new.name).to eq('x')
    end

    it 'returns default value specified as object even if value cannot be duplicated' do
      expect(doc_class.new.version).to eq(1)
    end

    it 'should save default values' do
      doc = doc_class.create!
      doc = doc_class.find(doc.id)
      expect(doc.name).to eq('x')
      expect(doc.uid).to eq(42)
      expect(doc.config).to eq({})
      expect(doc.version).to eq(1)
      expect(doc.hidden).to be false
    end

    it 'does not use default value if nil value assigns explicitly' do
      doc = doc_class.new(name: nil)
      expect(doc.name).to eq nil
    end
  end

  describe 'deprecated :float field type' do
    let(:doc) do
      Class.new do
        include Dynamoid::Document

        field :distance_m, :float

        def self.name
          'Document'
        end
      end.new
    end

    it 'acts as a :number field' do
      doc.distance_m = 5.33
      doc.save!
      doc.reload
      expect(doc.distance_m).to eq 5.33
    end

    it 'warns' do
      expect(Dynamoid.logger).to receive(:warn).with(/deprecated/)
      doc
    end
  end

  context 'single table inheritance (STI)' do
    let!(:class_a) do
      new_class do
        field :type
        field :a
      end
    end

    let!(:class_b) do
      Class.new(class_a) do
        field :b
      end
    end

    let!(:class_c) do
      Class.new(class_a) do
        field :c
      end
    end

    it 'enables only own attributes in a base class ' do
      expect(class_a.attributes.keys).to match_array(%i[id type a created_at updated_at])
    end

    it 'enabled only own attributes and inherited in a child class' do
      expect(class_b.attributes.keys).to include(:a)
      expect(class_b.attributes.keys).to include(:b)
      expect(class_b.attributes.keys).not_to include(:c)
    end
  end

  context 'extention overides field accessors' do
    let(:klass) do
      extention = Module.new do
        def name
          super.upcase
        end

        def name=(str)
          super(str.try(:downcase))
        end
      end

      Class.new do
        include Dynamoid::Document
        include extention

        field :name
      end
    end

    it 'can access new setter' do
      address = klass.new
      address.name = 'AB cd'
      expect(address[:name]).to eq('ab cd')
    end

    it 'can access new getter' do
      address = klass.new
      address.name = 'ABcd'
      expect(address.name).to eq('ABCD')
    end
  end

  describe '#write_attribute' do
    describe 'type casting' do
      it 'type casts attributes' do
        klass = new_class do
          field :count, :integer
        end

        obj = klass.new
        obj.write_attribute(:count, '101')
        expect(obj.attributes[:count]).to eql(101)
      end
    end
  end

  describe '#update_attribute' do
    describe 'type casting' do
      it 'type casts attributes' do
        klass = new_class do
          field :count, :integer
        end

        obj = klass.create
        obj.update_attribute(:count, '101')
        expect(obj.attributes[:count]).to eql(101)
        expect(raw_attributes(obj)[:count]).to eql(101)
      end
    end

    describe 'timestamps' do
      let(:klass) do
        new_class do
          field :title
        end
      end

      it 'sets updated_at if Config.timestamps=true', config: { timestamps: true } do
        obj = klass.create(title: 'Old title')

        travel 1.hour do
          time_now = Time.now
          obj.update_attribute(:title, 'New title')

          expect(obj.updated_at.to_i).to eql(time_now.to_i)
        end
      end

      it 'uses provided value updated_at if Config.timestamps=true', config: { timestamps: true } do
        obj = klass.create(title: 'Old title')

        travel 1.hour do
          updated_at = Time.now
          obj.update_attribute(:updated_at, updated_at)

          expect(obj.updated_at.to_i).to eql(updated_at.to_i)
        end
      end

      it 'does not raise error if Config.timestamps=false', config: { timestamps: false } do
        obj = klass.create(title: 'Old title')
        obj.update_attribute(:title, 'New title')

        expect(obj.updated_at).to eql(nil)
      end
    end
  end

  describe '#update_attributes' do
    describe 'type casting' do
      it 'type casts attributes' do
        klass = new_class do
          field :count, :integer
        end

        obj = klass.create
        obj.update_attributes(count: '101')
        expect(obj.attributes[:count]).to eql(101)
        expect(raw_attributes(obj)[:count]).to eql(101)
      end
    end

    describe 'timestamps' do
      let(:klass) do
        new_class do
          field :title
        end
      end

      it 'sets updated_at if Config.timestamps=true', config: { timestamps: true } do
        obj = klass.create(title: 'Old title')

        travel 1.hour do
          time_now = Time.now
          obj.update_attributes(title: 'New title')

          expect(obj.updated_at.to_i).to eql(time_now.to_i)
        end
      end

      it 'uses provided value updated_at if Config.timestamps=true', config: { timestamps: true } do
        obj = klass.create(title: 'Old title')

        travel 1.hour do
          updated_at = Time.now
          obj.update_attributes(updated_at: updated_at, title: 'New title')

          expect(obj.updated_at.to_i).to eql(updated_at.to_i)
        end
      end

      it 'does not raise error if Config.timestamps=false', config: { timestamps: false } do
        obj = klass.create(title: 'Old title')
        obj.update_attributes(title: 'New title')

        expect(obj.updated_at).to eql(nil)
      end
    end
  end
end
