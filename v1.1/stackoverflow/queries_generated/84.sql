-- {"query": "84.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 342} 
WITH ranked_posts AS (
    SELECT
        Id,
        Title,
        Body,
        OwnerUserId,
        CreationDate,
        Score,
        Rank() OVER (ORDER BY CreationDate DESC) AS post_rank
    FROM Posts
    WHERE PostTypeId = 1
),
top_users AS (
    SELECT
        Id,
        DisplayName,
        UpVotes,
        DownVotes,
        Reputation,
        Rank() OVER (ORDER BY Reputation DESC) AS user_rank
    FROM Users
),
user_post_votes AS (
    SELECT
        U.Id AS user_id,
        P.Id AS post_id,
        V.VoteTypeId
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    JOIN Votes V ON P.Id = V.PostId
    WHERE U.Reputation > 1000
),
popular_tags AS (
    SELECT
        TL.TagName,
        Count
    FROM Tags TL
    WHERE Count > 200
)
SELECT
    rp.Id AS post_id,
    rp.Title,
    tu.DisplayName AS owner_name,
    tu.Reputation AS owner_reputation,
    tu.UpVotes AS owner_upvotes,
    tu.DownVotes AS owner_downvotes,
    rp.CreationDate AS post_creation_date,
    rp.Score,
    tp.TagName AS popular_tag,
    upv.VoteTypeId
FROM ranked_posts rp
JOIN top_users tu ON rp.OwnerUserId = tu.Id
JOIN user_post_votes upv ON tu.Id = upv.user_id AND rp.Id = upv.post_id
JOIN popular_tags tp ON rp.Title LIKE '%' || tp.TagName || '%'
WHERE rp.post_rank <= 100 AND tu.user_rank <= 50;