// SPDX-FileCopyrightText: 2020 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-only

import React from "react";

import Box from "@material-ui/core/Box";
import Container from "@material-ui/core/Container";
import Grid from "@material-ui/core/Grid";
import Typography from "@material-ui/core/Typography";

import { Book } from "../domain/book";
import Cover from "./Cover";
import Layout from "./Layout";

type Props = {
  books: Book[];
  title: string;
};

const Library: React.VoidFunctionComponent<Props> = (props: Props) => {
  return (
    <Layout>
      <Container maxWidth="md">
        <Box my={4}>
          <Typography variant="h4" component="h1" gutterBottom>
            {props.title} {props.books.length > 0 && `(${props.books.length})`}
          </Typography>
        </Box>
      </Container>
      <Container maxWidth="md">
        <Grid container>
          {props.books.map((book: Book) => (
            <Grid item key={book.id} xs={6} sm={4} md={3}>
              <Cover book={book} />
            </Grid>
          ))}
        </Grid>
      </Container>
    </Layout>
  );
};
export default Library;
