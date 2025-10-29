-- {"query": "7603.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1972}
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_viewcount,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS score_rank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS user_post_count,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS user_avg_score,
        NTILE(4) OVER (ORDER BY p.Score) AS score_quartile,
        CASE 
            WHEN p.Score > 0 THEN 'Positive'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'Neutral'
        END AS score_category,
        COALESCE(p.Title, 'No Title') AS normalized_title,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN 
                -- count occurrences of '><' separators + 1 as a portable way to count tags stored like '<tag1><tag2>'
                (LENGTH(TRIM(BOTH '<' FROM REPLACE(REPLACE(p.Tags, '><', '|'), '>', ''))) - LENGTH(REPLACE(TRIM(BOTH '<' FROM REPLACE(REPLACE(p.Tags, '><', '|'), '>', '')), '|', '')) ) + 1
            ELSE 0 
        END AS tag_count,
        CASE 
            WHEN p.CommentCount > 0 AND NULLIF(p.ViewCount, 0) IS NOT NULL THEN (p.CommentCount * 100.0) / NULLIF(p.ViewCount, 0)
            ELSE 0 
        END AS comment_to_view_ratio,
        -- interval and epoch calculations; use timestamp subtraction and extract epoch where supported
        (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - CAST(p.CreationDate AS TIMESTAMP)) AS creation_interval,
        FLOOR(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - CAST(p.CreationDate AS TIMESTAMP))) / 86400) AS days_since_creation,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Unanswered' 
        END AS post_status
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= CAST('2020-01-01' AS TIMESTAMP)
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT rp.Id) AS total_posts,
        COUNT(DISTINCT CASE WHEN rp.PostTypeId = 1 THEN rp.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN rp.PostTypeId = 2 THEN rp.Id END) AS answer_count,
        SUM(rp.Score) AS total_score,
        AVG(rp.Score) AS avg_score,
        MAX(rp.Score) AS max_score,
        MIN(rp.Score) AS min_score,
        SUM(rp.ViewCount) AS total_views,
        MAX(rp.ViewCount) AS max_views,
        AVG(rp.ViewCount) AS avg_views,
        SUM(rp.CommentCount) AS total_comments,
        AVG(rp.CommentCount) AS avg_comments
    FROM Users u
    LEFT JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TopQuestions AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.Tags,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.post_status,
        CASE 
            WHEN rp.Score > 50 THEN 'Highly Upvoted'
            WHEN rp.Score > 20 THEN 'Moderately Upvoted'
            WHEN rp.Score > 0 THEN 'Slightly Upvoted'
            ELSE 'Downvoted or Neutral'
        END AS score_level,
        CASE 
            WHEN rp.ViewCount > 5000 THEN 'Viral'
            WHEN rp.ViewCount > 1000 THEN 'Popular'
            WHEN rp.ViewCount > 500 THEN 'Moderate'
            ELSE 'Low View'
        END AS view_level
    FROM RankedPosts rp
    WHERE rp.PostTypeId = 1 
      AND rp.score_rank <= 100
),
QuestionAnalysis AS (
    SELECT 
        tq.Id,
        tq.Title,
        tq.Score,
        tq.ViewCount,
        tq.AnswerCount,
        tq.CommentCount,
        tq.FavoriteCount,
        tq.Tags,
        tq.OwnerUserId,
        tq.CreationDate,
        tq.post_status,
        tq.score_level,
        tq.view_level,
        u.DisplayName AS author_name,
        u.Reputation AS author_reputation,
        u.Views AS author_views,
        u.UpVotes AS author_upvotes,
        u.DownVotes AS author_downvotes,
        CASE 
            WHEN u.Reputation < 1000 THEN 'Beginner'
            WHEN u.Reputation < 5000 THEN 'Intermediate'
            WHEN u.Reputation < 10000 THEN 'Advanced'
            ELSE 'Expert'
        END AS user_level,
        CASE 
            WHEN tq.AnswerCount = 0 THEN 'No Answers'
            WHEN tq.AnswerCount <= 1 THEN 'One Answer'
            WHEN tq.AnswerCount <= 5 THEN 'Few Answers'
            ELSE 'Many Answers'
        END AS answer_category,
        CASE 
            WHEN tq.CommentCount = 0 THEN 'No Comments'
            WHEN tq.CommentCount <= 1 THEN 'One Comment'
            WHEN tq.CommentCount <= 5 THEN 'Few Comments'
            ELSE 'Many Comments'
        END AS comment_category,
        CASE 
            WHEN tq.Score > 0 AND tq.AnswerCount > 0 THEN (tq.Score * 100.0) / NULLIF(tq.AnswerCount, 0)
            ELSE 0 
        END AS score_per_answer,
        CASE 
            WHEN tq.Score > 0 AND tq.CommentCount > 0 THEN (tq.Score * 100.0) / NULLIF(tq.CommentCount, 0)
            ELSE 0 
        END AS score_per_comment,
        (tq.Score * 1.0) / NULLIF(tq.ViewCount + tq.CommentCount + tq.AnswerCount, 0) AS normalized_score
    FROM TopQuestions tq
    LEFT JOIN Users u ON tq.OwnerUserId = u.Id
)
SELECT 
    qa.Id,
    qa.Title,
    qa.Score,
    qa.ViewCount,
    qa.AnswerCount,
    qa.CommentCount,
    qa.FavoriteCount,
    qa.Tags,
    qa.OwnerUserId,
    qa.CreationDate,
    qa.post_status,
    qa.score_level,
    qa.view_level,
    qa.author_name,
    qa.author_reputation,
    qa.author_views,
    qa.author_upvotes,
    qa.author_downvotes,
    qa.user_level,
    qa.answer_category,
    qa.comment_category,
    qa.score_per_answer,
    qa.score_per_comment,
    qa.normalized_score,
    CASE 
        WHEN qa.score_per_answer > 100 AND qa.score_per_comment > 10 THEN 'Highly Engaged'
        WHEN qa.score_per_answer > 50 OR qa.score_per_comment > 5 THEN 'Engaged'
        ELSE 'Low Engagement'
    END AS engagement_level,
    CASE 
        WHEN qa.normalized_score > 0.3 THEN 'Highly Valued'
        WHEN qa.normalized_score > 0.1 THEN 'Moderately Valued'
        ELSE 'Low Value'
    END AS value_level,
    CASE 
        WHEN qa.Score > 0 AND qa.view_level = 'Viral' THEN 'Viral Upvoted'
        WHEN qa.Score > 0 AND qa.view_level IN ('Popular', 'Moderate') THEN 'Popular Upvoted'
        ELSE 'Other'
    END AS viral_category,
    CASE 
        WHEN qa.CommentCount > qa.AnswerCount THEN 'More Comments Than Answers'
        WHEN qa.CommentCount < qa.AnswerCount THEN 'More Answers Than Comments'
        ELSE 'Equal Comments And Answers'
    END AS comment_answer_ratio,
    EXTRACT(YEAR FROM qa.CreationDate) AS post_year,
    EXTRACT(MONTH FROM qa.CreationDate) AS post_month,
    CASE 
        WHEN EXTRACT(DAY FROM qa.CreationDate) BETWEEN 1 AND 10 THEN 'First Decade'
        WHEN EXTRACT(DAY FROM qa.CreationDate) BETWEEN 11 AND 20 THEN 'Second Decade'
        WHEN EXTRACT(DAY FROM qa.CreationDate) BETWEEN 21 AND 31 THEN 'Third Decade'
        ELSE 'Unknown' 
    END AS post_decade
FROM QuestionAnalysis qa
WHERE qa.author_reputation > 500
  AND qa.score_level IN ('Highly Upvoted', 'Moderately Upvoted')
  AND qa.view_level IN ('Viral', 'Popular')
  AND (qa.score_per_answer > 20 OR qa.score_per_comment > 2)
  AND (
      CASE 
          WHEN qa.score_per_answer > 100 AND qa.score_per_comment > 10 THEN 'Highly Engaged'
          WHEN qa.score_per_answer > 50 OR qa.score_per_comment > 5 THEN 'Engaged'
          ELSE 'Low Engagement'
      END
  ) = 'Highly Engaged'
  AND (
      CASE 
          WHEN qa.normalized_score > 0.3 THEN 'Highly Valued'
          WHEN qa.normalized_score > 0.1 THEN 'Moderately Valued'
          ELSE 'Low Value'
      END
  ) = 'Highly Valued'
  AND (
      CASE 
          WHEN qa.Score > 0 AND qa.view_level = 'Viral' THEN 'Viral Upvoted'
          WHEN qa.Score > 0 AND qa.view_level IN ('Popular', 'Moderate') THEN 'Popular Upvoted'
          ELSE 'Other'
      END
  ) IN ('Viral Upvoted', 'Popular Upvoted')
ORDER BY qa.Score DESC, qa.ViewCount DESC, qa.normalized_score DESC
LIMIT 1000;