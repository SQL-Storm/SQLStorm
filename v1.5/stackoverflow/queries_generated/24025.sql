-- {"query": "24025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3435} 

WITH
    /** Extract tags from questions that contain the word “data” and have answers **/
    question_tags AS (
        SELECT
            p.OwnerUserId          AS user_id,
            unnest(string_to_array(regexp_replace(p.Tags, '[<>]', '', 'g'), '<')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Title ILIKE '%data%'
          AND p.AnswerCount > 0
    ),

    /** Extract tags from posts that are marked as duplicates (LinkTypeId = 3) **/
    duplicate_tags AS (
        SELECT
            p.OwnerUserId          AS user_id,
            unnest(string_to_array(regexp_replace(p.Tags, '[<>]', '', 'g'), '<')) AS tag
        FROM Posts p
        JOIN PostLinks pl
          ON pl.PostId = p.Id
         AND pl.LinkTypeId = 3
        WHERE p.PostTypeId = 1
    ),

    /** Combine both tag sources (set operator UNION ALL) **/
    all_tags AS (
        SELECT * FROM question_tags
        UNION ALL
        SELECT * FROM duplicate_tags
    ),

    /** Count occurrences of each tag per user **/
    tag_counts AS (
        SELECT
            user_id,
            tag,
            COUNT(*) AS tag_cnt
        FROM all_tags
        GROUP BY user_id, tag
    ),

    /** Rank tags for each user (window function) **/
    ranked_tags AS (
        SELECT
            user_id,
            tag,
            tag_cnt,
            RANK() OVER (PARTITION BY user_id ORDER BY tag_cnt DESC, tag) AS tag_rank
        FROM tag_counts
    ),

    /** Average up‑vote score on answers of each user **/
    avg_ans_score AS (
        SELECT
            p.OwnerUserId AS user_id,
            AVG(v.Score) FILTER (WHERE v.VoteTypeId = 2) AS avg_upvote
        FROM Posts p
        JOIN Votes v ON v.PostId = p.Id
        WHERE p.ParentId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    /** Count close votes on duplicate posts linked to each post **/
    close_votes AS (
        SELECT
            pl.RelatedPostId     AS post_id,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 6) AS close_cnt
        FROM PostLinks pl
        JOIN Votes v ON v.PostId = pl.RelatedPostId
        WHERE pl.LinkTypeId = 3
        GROUP BY pl.RelatedPostId
    ),

    /** Combine all information with outer joins, NULL handling, and a correlated subquery **/
    combined AS (
        SELECT
            u.Id                                   AS user_id,
            COALESCE(u.DisplayName, '(no name)')   AS user_display,

            rt.tag,
            rt.tag_cnt,

            COALESCE(ascore.avg_upvote, 0)        AS avg_upvote,

            COALESCE(cv.close_cnt, 0)             AS close_votes,

            CASE WHEN rt.tag_rank <= 3 THEN 'Top 3' ELSE 'Other' END
                                                  AS tag_group,

            /** Correlated sub‑query that counts the user’s questions **/
            (SELECT COUNT(*) FROM Posts p2
             WHERE p2.OwnerUserId = u.Id
               AND p2.PostTypeId = 1)              AS question_cnt
        FROM Users u
        LEFT JOIN ranked_tags rt    ON rt.user_id = u.Id
        LEFT JOIN avg_ans_score ascore ON ascore.user_id = u.Id
        LEFT JOIN close_votes cv    ON cv.post_id = rt.user_id -- for illustration
    )

SELECT
    user_id,
    user_display,
    tag,
    tag_cnt,
    avg_upvote,
    close_votes,
    tag_group,
    question_cnt
FROM combined
WHERE tag_cnt IS NOT NULL
  AND (avg_upvote > 5 OR close_votes > 0)
ORDER BY user_id, tag_rank
LIMIT 200;
