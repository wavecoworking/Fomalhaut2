import React from "react";

import Box from "@material-ui/core/Box";
import Container from "@material-ui/core/Container";
import Grid from "@material-ui/core/Grid";
import makeStyles from "@material-ui/core/styles/makeStyles";
import Typography from "@material-ui/core/Typography";

import { Book } from "../domain/book";
import { Collection } from "../domain/collection";
import Cover from "./cover";
import Layout from "./layout";

const useStyles = makeStyles({
  media: {
    height: 200,
    objectFit: "contain",
  },
  card: {
    //height: "100%",
  },
  filename: {
    display: "-webkit-box",
    WebkitLineClamp: 2,
    WebkitBoxOrient: "vertical",
    overflow: "hidden",
  },
});

type Props = {
  collections: Collection[];
  books: Book[];
};

const Library = (props: Props) => {
  const classes = useStyles();
  return (
    <Layout collections={props.collections}>
      <Container maxWidth="md">
        <Box my={4}>
          <Typography variant="h4" component="h1" gutterBottom>
            Book shelf name {props.books.length}
          </Typography>
        </Box>
      </Container>
      <Container maxWidth="md">
        <Grid container spacing={4}>
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
