-- {"query": "5.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 327} 
WITH ranked_posts AS (
    SELECT
        Id,
        Title,
        Score,
        ROW_NUMBER() OVER (ORDER BY Score DESC) AS rank
    FROM Posts
    WHERE PostTypeId = 1
),
top_users AS (
    SELECT
        U.Id,
        U.DisplayName,
        COALESCE(SUM(V.BountyAmount), 0) AS total_bounty
    FROM Users U
    LEFT JOIN Votes V ON U.Id = V.UserId AND V.VoteTypeId IN (8, 9)
    GROUP BY U.Id, U.DisplayName
),
top_tags AS (
    SELECT
        T.TagName,
        COUNT(PL.Id) AS link_count
    FROM Tags T
    JOIN PostLinks PL ON T.Id = PL.RelatedPostId
    GROUP BY T.TagName
),
user_stats AS (
    SELECT
        U.Id,
        U.Reputation,
        U.Views,
        COUNT(DISTINCT P.Id) AS question_count
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1
    GROUP BY U.Id, U.Reputation, U.Views
)
SELECT
    TP.DisplayName,
    TP.total_bounty,
    US.Reputation,
    US.Views,
    US.question_count,
    TT.TagName,
    TT.link_count,
    RP.Title,
    RP.Score,
    RP.rank
FROM top_users TP
JOIN user_stats US ON TP.Id = US.Id
CROSS JOIN top_tags TT
LEFT JOIN ranked_posts RP ON TP.Id = RP.Id
WHERE RP.rank <= 10;