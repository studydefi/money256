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
    <p>Mint by pooling DAI into the PricelessCFD contract:</p>
    <div>
      <button>Mint</button>
    </div>
    <p>Tokens you own: 4 long / 2 short</p>
    <p>Current CFD expiry date: 2020-06-01 12:00:00</p>
    <div>
      Redeem for minters (i.e. you must have equal amount of long/short tokens). Can be done anytime before settlement/expiry.
    </div>
      <div><button>Redeem</button></div>
    <div>
      Redeem all long/short tokens you own (after settlement/expiry): <button>Redeem</button>
    </div>
  </>
);
