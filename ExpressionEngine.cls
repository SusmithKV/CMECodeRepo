/*
 * Author: Mayank Solanki
 */
global class ExpressionEngine implements vlocity_cmt.VlocityOpenInterface {
    
    private static final Map<String, List<Object>> PREVIOUSLY_COMPILED_EXPRESSIONS = new Map<String, List<Object>>();

    public enum Operator {ADD, SUBTRACT, MULTIPLY, DIVIDE, BRACKET_START, BRACKET_END}
    private Set<String> OPERATORS = new Set<String>{'+', '-', '*', '/', '(', ')'};
   
    //OLD: [0-9]+\\.[0-9]+|[0-9]+|[+|\\-|/|*|%|\\(|\\)]|[a-zA-Z_ ]+
    //NEW: [0-9]+\\.[0-9]+|[0-9]+|{{[.]+}}|[+|\\-|/|*|%|\\(|\\)]
    private static Pattern EXPRESSION_PATTERN = Pattern.compile('[0-9]+\\.[0-9]+|[0-9]+|\\{\\{.+\\}\\}|[+|\\-|/|*|%|\\(|\\)]');

    global Boolean invokeMethod(String methodName, Map<String,Object> input, Map<String,Object> output, Map<String,Object> options){
        if ('tokenize'.equals(methodName)){
            String expression = (String) input.get('expression');
            output.put('tokens', tokenize(expression));
        }
        else if('calculate'.equals(methodName)){
            Object expressions =  input.get('input');
            List<Object> expressionInputs = new List<Object>();
            if(expressions instanceof String){
                String expressionStr =  (String) expressions;
                Map<String, Object> variableValues = new Map<String, Object>();
                if(input.containsKey('variableValues')){
                    variableValues = (Map<String, Object>) input.get('variableValues');
                }
                
                expressionInputs.add(new Map<String, Object>{
                    'expression' => expressionStr,
                    'variableValues' => variableValues
                });
                    
             }
            
            if (expressions instanceof List<Object>){
               
                expressionInputs = (List<Object>) expressions;
            }
            
            List<Map<String, Object>> outputItems = new List<Map<String, Object>>();
            for (Integer i=0; i<expressionInputs.size(); i++) {
                Map<String, Object> expressionInput = (Map<String, Object>) expressionInputs[i];
                
                String expressionStr = (String) expressionInput.get('expression');
                Map<String, Object> variableValues = new Map<String, Object>();

                Map<String, Object> outputItem = new Map<String, Object>();                
                if(!String.isBlank(expressionStr)){
                    try {
                        if (expressionInput.containsKey('variableValues')) {
                            variableValues = (Map<String, Object>) expressionInput.get('variableValues');
                        }
                        
                        Decimal expresisonValue = evaluateExpression(expressionStr, variableValues);
                        
                        outputItem.put('result','success');
                        outputItem.put('output', expresisonValue);
                    }
                    catch(Exception ex) {
                        System.debug(ex.getStackTraceString());
                        outputItem.put('result','error');
                        outputItem.put('errorMessage', ex.getMessage());
                        outputItem.put('exception', ex);
                    }
                }
                else {
                    outputItem.put('result','error');
                    outputItem.put('errorMessage','expression is Blank');
                }
                
                outputItem.put('index', i);
                outputItems.add(outputItem);
            }
            
            if(outputItems.size()==1){
                output.putAll(outputItems[0]);
            }
            else {
                output.put('output', outputItems); 
            }
        }
        return true;
    }
    
    private Decimal evaluateExpression(String expression, Map<String, Object> variableValues){
        List<Object> postFixTokens;     
        if(!PREVIOUSLY_COMPILED_EXPRESSIONS.containsKey(expression)){
            List<Object> infixTokens = tokenize(expression);
            postFixTokens = infixToPostFix(infixTokens);
            
            PREVIOUSLY_COMPILED_EXPRESSIONS.put(expression, postFixTokens);
        }
        else {
            postFixTokens = PREVIOUSLY_COMPILED_EXPRESSIONS.get(expression);
        }
        
        replaceVariables(postFixTokens, variableValues);

        return evaluate(postFixTokens);
        
    }
    
    
    @TestVisible
    private List<Object> tokenize(String expression) {
        List<Object> tokens = new List<Object>();
        Matcher expMatcher = EXPRESSION_PATTERN.matcher(expression);
        
        while(expMatcher.find()){
            String match = expMatcher.group(0).trim();
            Object matchingToken;
            if (!String.isBlank(match)) {
                
                if(match.startsWith('{{') && match.endsWith('}}')){
                    String variableName = match.removeStart('{{').removeEnd('}}').trim();
                    if(!String.isEmpty(variableName)){
                        matchingToken = variableName;
                    }
                    
                }
                if(OPERATORS.contains(match)){
                    switch on match {
                        when '+' {matchingToken = Operator.ADD;}
                        when '-' {matchingToken = Operator.SUBTRACT;}
                        when '*' {matchingToken = Operator.MULTIPLY;}
                        when '/' {matchingToken = Operator.DIVIDE;}
                        when '(' {matchingToken = Operator.BRACKET_START;}
                        when ')' {matchingToken = Operator.BRACKET_END;}
                    }
                }
                else {
                    try {
                        matchingToken = Decimal.valueOf(match);
                       }
                    catch(TypeException ex){
                        //ignore
                    }
                }
                
                if (matchingToken != null){
                    tokens.add(matchingToken);  
                }
                
            }
        }
        
        return tokens;
    }
    
    

    @TestVisible
    private Decimal evaluate(List<Object> postFixTokens){
        StackDec operandStack = new StackDec();
        
        for(Integer i=0; i<postFixTokens.size(); i++){
            Object token = postFixTokens[i];
            
            if (token instanceof Decimal) {
                operandStack.push((Decimal) token);                       
            }
            else if (token instanceof Operator) {
                
                Operator operator = (Operator) token;
                Decimal secondOperand = operandStack.pop(); //intentionally in reverse order
                Decimal firstOperand = operandStack.pop(); //intentionally in reverse order
                
                operandStack.push(evaluateOperator(operator, firstOperand, secondOperand));
            }
        }
        
        if (operandStack.size() != 1){
            throw new ExpressionEngineException('Error in running postFixExpression'+JSON.serialize(postFixTokens));
        }
        return operandStack.pop();
        
    }
    
    private Decimal evaluateOperator(Operator operator, Decimal firstOperand, Decimal secondOperand){
        Decimal result;
        
        switch on operator {
            when ADD {
                result = firstOperand + secondOperand;
            }
            when SUBTRACT {
                result = firstOperand - secondOperand;
            }
            when MULTIPLY {
                result = firstOperand * secondOperand;
            }
            when DIVIDE {
                result = firstOperand / secondOperand;
            }
            when else {
                throw new ExpressionEngineException('Unknown Operator: ' + operator);
            }
        }
        
        return result;
    }
    
    @TestVisible
    private void replaceVariables(List<Object> tokens, Map<String, Object> variableValues) {
        for (Integer i=0; i<tokens.size(); i++) {
            Object token = tokens[i];
            
            if (token instanceof String) {
                String variableName = (String) token;

                if(variableValues.containsKey(variableName)){
                    Object variableValue = variableValues.get(variableName);
                    
                    if (variableValue instanceof Decimal) {
                        tokens[i] = (Decimal) variableValue;                        
                    }
                    else if (variableValue instanceof String) {
                        try {
                          tokens[i] = Decimal.valueOf((String) variableValue);  
                        }
                        catch(TypeException ex) {
                            //ignore
                        } 
                    }
                    else {
                        throw new ExpressionEngineException('Value for the variable is not available :' + variableName);
                    }
                }
                else {
                   throw new ExpressionEngineException('Value for the variable is not available :' + variableName);
                }
            }
        } 
    }
       
    @TestVisible
    private List<Object> infixToPostFix(List<Object> infixTokens) {
        List<Object> postFixTokens = new List<Object>();
        Stack operatorStack = new Stack();        
        for (Integer i=0; i<infixTokens.size(); i++){
            Object token = infixTokens[i];
            
            if(token instanceof Decimal || token instanceof String) {
                postFixTokens.add(token);
                System.debug(String.format('Flow: Add({0}), postfixExpr', new List<Object>{token}));
            }
            else if(token instanceof Operator) {
                Operator scannedOpr = (Operator) token;
                if (operatorStack.isEmpty()) {
                    System.debug(String.format('Flow: Push({0}), Operator stack is empty', new List<Object>{token}));
                    operatorStack.push(scannedOpr);
                }
                else {
                    Operator stkTop = operatorStack.peek();
                    
                    if(scannedOpr == Operator.BRACKET_START){
                        operatorStack.push(scannedOpr);
                        System.debug(String.format('Flow: Push({0}), scanned operator is bracket start', new List<Object>{token}));
                    }
                    else if(scannedOpr == Operator.BRACKET_END) {
                        while(operatorStack.peek() != Operator.BRACKET_START){
                            Operator popedOpr = operatorStack.pop();
                            postFixTokens.add(popedOpr);
                            System.debug(String.format('Flow: Pop({0}), Operator is bracket end', new List<Object>{popedOpr}));
                        }
                        operatorStack.pop();
                    }
                    else if (stkTop == Operator.BRACKET_START || getPrecedence(scannedOpr, stkTop) > 0){
                        operatorStack.push(scannedOpr);  
                        System.debug(String.format('Flow: Push({0}), hasHigherPrecedence', new List<Object>{scannedOpr}));
                    }
                    else {
                        while(!operatorStack.isEmpty() && (operatorStack.peek() == Operator.BRACKET_START || getPrecedence(scannedOpr, operatorStack.peek())<1)) {
                            
                            if(operatorStack.peek() == Operator.BRACKET_START){
                                break;
                            }
                            
                            Operator popedOpr = operatorStack.pop();
                            postFixTokens.add(popedOpr);
                            System.debug(String.format('Flow: Pop({0}), not hasHigherPrecedence', new List<Object>{popedOpr}));
                        } 
                        
                        operatorStack.push(scannedOpr);
                        System.debug(String.format('Flow: Push({0}), not hasHigherPrecedence', new List<Object>{scannedOpr}));
                    }
                }
            }
            else {
               throw new ExpressionEngineException('Unexpected token :' + token); 
            }
            
            System.debug('Flow: Expr:' + JSON.serialize(postFixTokens));
            System.debug('Flow: Stack:' + JSON.serialize(operatorStack));
        }
        
        while(!operatorStack.isEmpty()){
            postFixTokens.add(operatorStack.pop());
        }
        
        return postFixTokens; 
    }
    
    Map<Object, Integer> OPERATOR_TO_INDEX = new Map<Object, Integer>{
        Operator.ADD => 0, Operator.SUBTRACT => 1, Operator.MULTIPLY => 2, Operator.DIVIDE => 3
    };
    
    //
    //0 == equal
    //1 == higher
    //-1 == lower
    List<List<Integer>> oprPrecedence = new List<List<Integer>>{
        //                +  -   *   /                   
        new List<Integer>{0, 0, -1, -1},  // +
        new List<Integer>{0, 0, -1, -1},  // -
        new List<Integer>{1, 1,  0,  0},  // *
        new List<Integer>{1, 1,  0,  0}   // /
    };
        
    private Integer getPrecedence(Operator firstOpr, Operator secondOpr){
        System.debug('firstOpr:'+firstOpr);
        System.debug('secondOpr:'+secondOpr);
        Integer firstOprIntex = OPERATOR_TO_INDEX.get(firstOpr);
        Integer secondOprIntex = OPERATOR_TO_INDEX.get(secondOpr);
        
        return oprPrecedence[firstOprIntex][secondOprIntex];
    }

    public class ExpressionEngineException extends Exception {}
    
    public class Stack {
        
        public List<Operator> items;
        
        public Stack(){
           items = new List<Operator>(); 
        }

        public void push(Operator item) {
            items.add(item);
        }
        
        public Operator pop() {
            Operator item = items.remove(items.size()-1);
            return item;
        }
        
        public Operator peek() {
            return items[items.size()-1];
        }
        
        public Boolean isEmpty() {
            return items.isEmpty();
        }
        
        public override String toString(){
            return JSON.serialize(items);
        }
    }
    
    public class StackDec {
        
        public List<Decimal> items;
        
        public StackDec(){
           items = new List<Decimal>(); 
        }

        public void push(Decimal item) {
            items.add(item);
        }
        
        public Decimal pop() {
            Decimal item = items.remove(items.size()-1);
            return item;
        }
        
        public Decimal peek() {
            return items[items.size()-1];
        }
        
        public Boolean isEmpty() {
            return items.isEmpty();
        }
        
        public Integer size() {
            return items.size();
        }
        
        public override String toString(){
            return JSON.serialize(items);
        }
    }
}
