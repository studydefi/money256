import React from "react";
import styled from "styled-components";

const Title = styled.h1`
  font-size: 50px;
  color: ${({ theme }) => theme.colors.primary};
`;

export default () => (
  <>
    <Title>Money256</Title>
    <p>A priceless CFD example</p>
    <p>'mint' button (which calls the mint function in PricelessCFD</p>
    <div>
      <button>Mint</button>
    </div>
    <p>A table to preview the long/short tokens you haev</p>
    <div>Insert table here</div>
    <p>A table to view when this PricelessCFD is gonna expire</p>
    <div>Insert table here</div>
    <p>
      A button to redeem back 1 long + 1 short tokens for DAI ('redeem'
      function)
    </p>
    <div>
      Redeem for minters (i.e. you have equal amount of long/short tokens)
      <button>Redeem</button>
    </div>
    <p>A redeemFinal function so ppl can redeem after expiration</p>
    <div>
      Redeem for everyone else after settlement<button>Redeem</button>
    </div>
  </>
);
