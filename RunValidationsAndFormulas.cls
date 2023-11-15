/*****
* Author: Susmith K V
* Contact: susmith.kv@salesforce.com
**/
global class RunValidationsAndFormulas implements vlocity_cmt.VlocityOpenInterface{
    
    //Use this only if going with Custom metadata-based pricing.
    Static Map<String,List<Infiwave_Tier_Based_Pricing__mdt>> productTierPricingList = new Map<String,List<Infiwave_Tier_Based_Pricing__mdt>>();
    global RunValidationsAndFormulas(){
        if(cache.Org.contains('local.ICInternalPartition.productTierPricingList')){
            productTierPricingList = (Map<String,List<Infiwave_Tier_Based_Pricing__mdt>>)cache.Org.get('local.ICInternalPartition.productTierPricingList');
            vlocity_cmt.FlowStaticMap.flowMap.put('productTierPricingList', productTierPricingList);
        }
    }
    //Use the above code only if going with custom metadata-based pricing.
    global Boolean invokeMethod (String methodName,
                                 Map<String, Object> input,
                                 Map<String, Object> output,
                                 Map<String, Object> options)
    {
        
        if (methodName == 'updateQuantityRollup')
        {
            updateQuantityRollup(input, output, options);
        }
        return true;    
    }
    
    private void updateQuantityRollup(Map<String, Object> input,
                                      Map<String, Object> output,
                                      Map<String, Object> options)
    {
        // Fetching Tier Based Pricing for further calculations.
        //Use this only if going with Custom metadata-based pricing.
        if(productTierPricingList.size() == 0){
            Map<String, Infiwave_Tier_Based_Pricing__mdt> tierBasesPricingRecords = Infiwave_Tier_Based_Pricing__mdt.getAll();
            for(Infiwave_Tier_Based_Pricing__mdt tierValue : tierBasesPricingRecords.values()){
                if(productTierPricingList.containsKey(tierValue.Product_Code__c)){
                    productTierPricingList.get(tierValue.Product_Code__c).add(tierValue);
                }else{
                    productTierPricingList.put(tierValue.Product_Code__c, new List<Infiwave_Tier_Based_Pricing__mdt>{tierValue});
                }
            }
            vlocity_cmt.FlowStaticMap.flowMap.put('productTierPricingList', productTierPricingList);
            Cache.Org.put('local.ICInternalPartition.productTierPricingList',productTierPricingList);
        }
        //Use this only if going with Custom metadata-based pricing.
        
        SObject parent = (SObject) vlocity_cmt.PricingPlanService.getFromPricingContext('Parent');
        List<SObject> itemList = (List<SObject>)vlocity_cmt.PricingPlanService.getFromPricingContext('LineItemList');
        //itemList.Sort();
        Id parentId = (Id)parent.get('Id');
        String sObjName = parentId.getSObjectType().getDescribe().getName();
        Map<String,Integer> qtyPerRootProductMap = new Map<String,Integer>();
        //Collecting the list of products for tierbasedpricing for later reference
        set<String> productsWithTierBasedPricing = new Set<String>();
        if(sObjName == 'Order'){
            for(SObject xli: itemList)              
            {
                String rootItemId = String.valueOf(xli.get('vlocity_cmt__RootItemId__c'));
                String assetRefId = String.valueOf(xli.get('vlocity_cmt__AssetReferenceId__c'));
                if(rootItemId != assetRefId){
                    if(qtyPerRootProductMap.containsKey(rootItemId)){
                        Integer qtySum = qtyPerRootProductMap.get(rootItemId) + Integer.valueOf(xli.get('Quantity'));
                        qtyPerRootProductMap.put(rootItemId,qtySum);
                    }else{
                        qtyPerRootProductMap.put(rootItemId,Integer.valueOf(xli.get('Quantity')));        
                    }                
                }
            }
            for(SObject xli: itemList)
            {
                String rootItemId = String.valueOf(xli.get('vlocity_cmt__RootItemId__c'));
                String assetRefId = String.valueOf(xli.get('vlocity_cmt__AssetReferenceId__c'));
                if(rootItemId == assetRefId){
                    String prodCode = String.valueOf(xli?.getSObject('PricebookEntry')?.getSObject('Product2')?.get('ProductCode')); 
                    Set<String> prodswithRollUpChildQuantity = new Set<String>(System.Label.RollUpChildQuantityProducts.split(';'));
                    if(prodswithRollUpChildQuantity.contains(prodCode)){
                        if(qtyPerRootProductMap.containsKey(assetRefId)){
                            xli.put('Quantity',qtyPerRootProductMap.get(assetRefId));
                        }
                        productsWithTierBasedPricing.add(prodCode);
                    }
                }
            }
            if(!productsWithTierBasedPricing.isEmpty()){
                vlocity_cmt.FlowStaticMap.flowMap.put('productsWithTier', productsWithTierBasedPricing);
            }
        }
    }   
}
