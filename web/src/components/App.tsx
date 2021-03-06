// SPDX-FileCopyrightText: 2020 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-only

import React, { useEffect, useReducer } from "react";
import { RoconRoot } from "rocon/react";

import { Book } from "../domain/book";
import { Collection } from "../domain/collection";
import {
  initialState,
  LoadingState,
  reducer,
  setBooks,
  setCollections,
  setLoading,
  StateContext,
} from "../reducer";
import Routes from "./Routes";

const parseBook = (book: Book): Book =>
  new Book(book.id, book.name, book.pageCount, book.readCount, book.like);

const App: React.VoidFunctionComponent = () => {
  const [state, dispatch] = useReducer(reducer, initialState);
  useEffect(() => {
    let unmounted = false;
    // Fetch All books
    async function fetchBooks() {
      const books = await fetch("/api/v1/books")
        .then((response) => response.json())
        .then((books: Book[]) => books.map((book) => parseBook(book)));
      if (!unmounted) {
        dispatch(setBooks(books));
      }
    }
    async function fetchCollections() {
      const collections: Collection[] = await fetch("/api/v1/collections")
        .then((response) => response.json())
        .then((collections: Collection[]) =>
          collections.map(
            (collection) =>
              new Collection(
                collection.id,
                collection.name,
                collection.books.map((book) => parseBook(book))
              )
          )
        );
      if (!unmounted) {
        dispatch(setCollections(collections));
      }
    }
    dispatch(setLoading(LoadingState.Loading));
    Promise.all([fetchBooks(), fetchCollections()])
      .then(() => setLoading(LoadingState.Loaded))
      .catch((error) => {
        console.error(error);
        dispatch(setLoading(LoadingState.Error));
      });
    return () => {
      unmounted = true;
    };
  }, []);

  return (
    <StateContext.Provider value={state}>
      <RoconRoot>
        <Routes />
      </RoconRoot>
    </StateContext.Provider>
  );
};
export default App;
