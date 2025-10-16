-- {"query": "98.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 214} 
WITH ranked_posts AS (
    SELECT
        Id,
        Title,
        CreationDate,
        Score,
        OwnerUserId,
        RANK() OVER (ORDER BY Score DESC) AS score_rank
    FROM
        Posts
    WHERE
        PostTypeId = 1
),
top_users AS (
    SELECT
        Id,
        DisplayName,
        Reputation,
        RANK() OVER (ORDER BY Reputation DESC) AS reputation_rank
    FROM
        Users
),
top_posts_and_users AS (
    SELECT
        rp.Id AS post_id,
        rp.Title AS post_title,
        rp.CreationDate AS post_creation_date,
        rp.Score AS post_score,
        ru.Id AS user_id,
        ru.DisplayName AS user_display_name,
        ru.Reputation AS user_reputation
    FROM
        ranked_posts rp
    JOIN top_users ru ON rp.OwnerUserId = ru.Id
    WHERE
        rp.score_rank <= 10
        AND ru.reputation_rank <= 10
)
SELECT
    *
FROM
    top_posts_and_users;