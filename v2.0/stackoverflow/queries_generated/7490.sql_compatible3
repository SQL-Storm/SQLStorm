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
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        SUM(COALESCE(p.Score, 0)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS UNBOUNDED PRECEDING) as cumulative_score,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags <> '' THEN 
                cardinality(string_to_array(trim(BOTH '<>' FROM p.Tags), '><')) 
            ELSE 0 
        END as tag_count,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 
                ROUND((p.AnswerCount * 100.0) / (p.AnswerCount + 1), 2)
            ELSE 0 
        END as answer_rate
    FROM Posts p
    WHERE p.CreationDate >= DATE '2022-01-01' 
      AND p.Score >= 0
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        SUM(COALESCE(p.Score, 0)) as total_score,
        AVG(COALESCE(p.Score, 0)) as avg_score,
        MAX(p.CreationDate) as last_post_date,
        COALESCE(MIN(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END), u.CreationDate) as first_question_date
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= DATE '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId, u.CreationDate
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p.ViewCount, 0) as wiki_views,
        CASE 
            WHEN t.Count > 100 AND t.IsRequired = TRUE THEN 'HighValueRequired'
            WHEN t.Count > 50 AND t.IsRequired = FALSE THEN 'HighValueOptional'
            WHEN t.Count <= 50 THEN 'LowValue'
            ELSE 'Unknown'
        END as tag_category,
        RANK() OVER (ORDER BY t.Count DESC) as popularity_rank
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
    WHERE t.Count > 0
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, p.ViewCount, t.IsRequired
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn,
        DENSE_RANK() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as activity_sequence,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as prev_activity_date,
        CASE 
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'ModerationAction'
            WHEN ph.PostHistoryTypeId IN (1, 4, 5, 6, 7, 8, 9) THEN 'EditAction'
            WHEN ph.PostHistoryTypeId IN (31, 32, 33, 34, 35, 36) THEN 'CommunityAction'
            ELSE 'Other'
        END as activity_type
    FROM PostHistory ph
    WHERE ph.CreationDate >= DATE '2022-01-01'
      AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 31, 32, 33, 34, 35, 36)
),
ComplexFilter AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.tag_count,
        rp.answer_rate,
        COALESCE(us.total_posts, 0) as user_total_posts,
        COALESCE(us.questions, 0) as user_questions,
        COALESCE(us.answers, 0) as user_answers,
        COALESCE(us.total_score, 0) as user_total_score,
        COALESCE(us.avg_score, 0) as user_avg_score,
        CASE 
            WHEN COALESCE(us.total_score,0) > 1000 AND COALESCE(us.total_posts,0) > 50 THEN 'HighPerformer'
            WHEN COALESCE(us.total_score,0) > 100 AND COALESCE(us.total_posts,0) > 10 THEN 'ModeratePerformer'
            WHEN COALESCE(us.total_posts,0) <= 10 THEN 'NewUser'
            ELSE 'Other'
        END as user_performance,
        COALESCE(ta.TagName, 'NoTag') as main_tag,
        COALESCE(ta.tag_category, 'UnknownCat') as tag_category,
        COALESCE(pa.activity_type, 'NoActivity') as recent_activity,
        CASE 
            WHEN rp.CreationDate > DATE '2022-06-01' THEN 'Recent'
            WHEN rp.CreationDate BETWEEN DATE '2021-01-01' AND DATE '2022-05-31' THEN '2021'
            WHEN rp.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2020-12-31' THEN '2020'
            ELSE 'Before2020'
        END as time_period
    FROM RankedPosts rp
    LEFT JOIN UserStats us ON rp.OwnerUserId = us.UserId
    LEFT JOIN TagAnalysis ta ON rp.Tags IS NOT NULL 
        AND cardinality(string_to_array(trim(BOTH '<>' FROM rp.Tags), '><')) > 0
        AND ta.TagName = (
            SELECT TRIM(BOTH '<>' FROM tag) 
            FROM unnest(string_to_array(trim(BOTH '<>' FROM rp.Tags), '><')) AS tag
            ORDER BY length(tag) DESC LIMIT 1
        )
    LEFT JOIN PostActivity pa ON rp.Id = pa.PostId 
        AND pa.rn = 1 
        AND pa.activity_sequence > 0
    WHERE rp.rn = 1
      AND (
          (rp.Score > 10 AND rp.ViewCount > 100) 
          OR (rp.AnswerCount > 1 AND rp.answer_rate > 50)
          OR (rp.Score > 0 AND rp.tag_count > 2)
          OR (COALESCE(us.total_posts, 0) > 100 AND COALESCE(us.avg_score, 0) > 5)
      )
)
SELECT 
    cf.Id,
    cf.PostTypeId,
    cf.Score,
    cf.ViewCount,
    cf.CreationDate,
    cf.OwnerUserId,
    cf.Title,
    cf.Tags,
    cf.AnswerCount,
    cf.user_performance,
    cf.user_total_posts,
    cf.user_questions,
    cf.user_answers,
    cf.user_total_score,
    cf.main_tag,
    cf.tag_category,
    cf.recent_activity,
    cf.time_period,
    CASE 
        WHEN cf.Score * 1000 + cf.ViewCount > 10000 THEN 'VeryPopular'
        WHEN cf.Score * 100 + cf.AnswerCount * 10 > 500 THEN 'Popular'
        WHEN cf.Score * 50 + cf.ViewCount > 200 THEN 'Moderate'
        ELSE 'Low'
    END as popularity_level,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - cf.CreationDate))/86400 AS INTEGER) as days_since_creation,
    CASE 
        WHEN cf.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.CreationDate >= DATE '2022-01-01') 
        THEN 'AboveAvg'
        WHEN cf.Score < (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.CreationDate >= DATE '2022-01-01') 
        THEN 'BelowAvg'
        ELSE 'Avg'
    END as score_comparison,
    COALESCE(
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cf.Id AND c.Score > 0),
        0
    ) as positive_comments,
    COALESCE(
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cf.Id AND v.VoteTypeId IN (2, 3)),
        0
    ) as total_votes,
    CASE 
        WHEN cf.AnswerCount > 0 THEN 
            ROUND((cf.AnswerCount * 100.0) / NULLIF(cf.AnswerCount + COALESCE((SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = cf.Id), 0), 0), 2)
        ELSE NULL
    END as answer_to_comment_ratio,
    CASE 
        WHEN cf.ViewCount > 0 AND cf.Score > 0 THEN 
            ROUND(cf.Score::numeric / NULLIF(cf.ViewCount, 0), 6)
        ELSE 0 
    END as score_per_view,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = cf.Id AND pl.LinkTypeId = 3) as duplicate_link_count,
    COALESCE(
        (SELECT string_agg(t.TagName, ', ') 
         FROM Tags t 
         WHERE t.TagName IN (
             SELECT TRIM(BOTH '<>' FROM tag) 
             FROM unnest(string_to_array(trim(BOTH '<>' FROM cf.Tags), '><')) AS tag
         )
         AND t.Count > 50),
        'LowPopularityTags'
    ) as high_value_tags
FROM ComplexFilter cf
WHERE cf.user_performance IN ('HighPerformer', 'ModeratePerformer')
  AND cf.tag_category IN ('HighValueRequired', 'HighValueOptional')
  AND cf.time_period IN ('Recent', '2021')
  AND (
    CASE 
        WHEN cf.Score > (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.CreationDate >= DATE '2022-01-01') THEN 'AboveAvg'
        WHEN cf.Score < (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.CreationDate >= DATE '2022-01-01') THEN 'BelowAvg'
        ELSE 'Avg'
    END
  ) IN ('AboveAvg', 'Avg')
  AND (
      CASE 
        WHEN cf.Score * 1000 + cf.ViewCount > 10000 THEN 'VeryPopular'
        WHEN cf.Score * 100 + cf.AnswerCount * 10 > 500 THEN 'Popular'
        WHEN cf.Score * 50 + cf.ViewCount > 200 THEN 'Moderate'
        ELSE 'Low'
      END
  ) IN ('VeryPopular', 'Popular')
  AND (
      cf.Score > 50 
      OR cf.AnswerCount > 10 
      OR cf.ViewCount > 1000
  )
ORDER BY 
    cf.Score DESC,
    cf.ViewCount DESC,
    cf.CreationDate DESC
LIMIT 1000;