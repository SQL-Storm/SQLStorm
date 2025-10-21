-- {"query": "55088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1982} 

/*  Benchmark query: deep user‑centric analytics with many joins, CTEs, window functions and JSON aggregation  */
WITH 
-- 1. Base user info
base_users AS (
    SELECT 
        u.Id                          AS UserId,
        u.DisplayName,
        u.CreationDate                AS UserCreated,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes
    FROM   Users u
),

-- 2. Aggregate post statistics per user
post_stats AS (
    SELECT 
        p.OwnerUserId                 AS UserId,
        COUNT(*)                      AS TotalPosts,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS Questions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS Answers,
        SUM(p.Score)                  AS ScoreSum,
        AVG(p.Score)                  AS ScoreAvg,
        MAX(p.CreationDate)           AS LastPostDate,
        SUM(p.ViewCount)              AS TotalViews,
        SUM(p.FavoriteCount)          AS TotalFavorites,
        SUM(p.AnswerCount)            AS SumAnswerCount,
        SUM(p.CommentCount)           AS SumCommentCount
    FROM   Posts p
    WHERE  p.OwnerUserId IS NOT NULL
    GROUP  BY p.OwnerUserId
),

-- 3. Vote aggregates (only up‑ and down‑votes on posts owned by the user)
vote_stats AS (
    SELECT 
        p.OwnerUserId                               AS UserId,
        COUNT(v.Id)                                 AS TotalVotesReceived,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2)    AS UpVotesReceived,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3)    AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) 
                                                     AS NetUpVotes
    FROM   Posts p
    JOIN   Votes v ON v.PostId = p.Id
    WHERE  p.OwnerUserId IS NOT NULL
      AND  v.VoteTypeId IN (2,3)        -- up & down votes only
    GROUP  BY p.OwnerUserId
),

-- 4. Badge summary per user, aggregated as JSON
badge_summary AS (
    SELECT 
        b.UserId,
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'Name',  b.Name,
                'Class', b.Class,
                'TagBased', b.TagBased,
                'Date',  b.Date
            )
            ORDER BY b.Date DESC
        ) AS BadgesJson,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount
    FROM   Badges b
    GROUP  BY b.UserId
),

-- 5. Recent activity (last 5 posts + last 5 comments) per user using window functions
recent_activity AS (
    SELECT *
    FROM (
        SELECT 
            p.OwnerUserId                              AS UserId,
            p.Id                                       AS PostId,
            p.Title,
            p.CreationDate,
            'Post'                                     AS Type,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM   Posts p
        WHERE  p.OwnerUserId IS NOT NULL
        UNION ALL
        SELECT 
            c.UserId,
            c.Id,
            c.Text,
            c.CreationDate,
            'Comment',
            ROW_NUMBER() OVER (PARTITION BY c.UserId ORDER BY c.CreationDate DESC)
        FROM   Comments c
        WHERE  c.UserId IS NOT NULL
    ) a
    WHERE a.rn <= 5
),

-- 6. Tag participation – count distinct tags used in questions and answers
tag_participation AS (
    SELECT 
        p.OwnerUserId                               AS UserId,
        COUNT(DISTINCT UNNEST(string_to_array(
                TRIM(BOTH '<>' FROM p.Tags), '><'
            )) )                                   AS DistinctTagsUsed,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) 
                                                    AS QuestionsWithTags,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) 
                                                    AS AnswersWithTags
    FROM   Posts p
    WHERE  p.OwnerUserId IS NOT NULL
      AND  p.Tags IS NOT NULL
    GROUP  BY p.OwnerUserId
),

-- 7. Closed / reopened history – number of times user’s posts were closed or reopened
closure_stats AS (
    SELECT 
        ph.UserId                                   AS UserId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS TimesClosed,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS TimesReopened
    FROM   PostHistory ph
    WHERE  ph.PostHistoryTypeId IN (10,11)
      AND  ph.UserId IS NOT NULL
    GROUP  BY ph.UserId
)

-- Final assembled result
SELECT 
    bu.UserId,
    bu.DisplayName,
    bu.CreationDate                         AS AccountCreated,
    bu.Reputation,
    bu.Views,
    bu.UpVotes,
    bu.DownVotes,

    COALESCE(ps.TotalPosts,0)               AS TotalPosts,
    COALESCE(ps.Questions,0)                AS TotalQuestions,
    COALESCE(ps.Answers,0)                  AS TotalAnswers,
    COALESCE(ps.ScoreSum,0)                 AS TotalScore,
    COALESCE(ps.ScoreAvg,0)                 AS AvgScore,
    ps.LastPostDate,
    COALESCE(ps.TotalViews,0)               AS PostsViews,
    COALESCE(ps.TotalFavorites,0)           AS PostsFavorites,
    COALESCE(ps.SumAnswerCount,0)           AS SumAnswerCount,
    COALESCE(ps.SumCommentCount,0)          AS SumCommentCount,

    COALESCE(vs.TotalVotesReceived,0)       AS VotesReceived,
    COALESCE(vs.UpVotesReceived,0)          AS UpVotesReceived,
    COALESCE(vs.DownVotesReceived,0)        AS DownVotesReceived,
    COALESCE(vs.NetUpVotes,0)               AS NetUpVotes,

    COALESCE(bs.GoldCount,0)                AS GoldBadges,
    COALESCE(bs.SilverCount,0)              AS SilverBadges,
    COALESCE(bs.BronzeCount,0)              AS BronzeBadges,
    bs.BadgesJson,

    COALESCE(tp.DistinctTagsUsed,0)         AS DistinctTagsUsed,
    COALESCE(tp.QuestionsWithTags,0)        AS QsWithTags,
    COALESCE(tp.AnswersWithTags,0)          AS AsWithTags,

    COALESCE(cs.TimesClosed,0)              AS PostsClosed,
    COALESCE(cs.TimesReopened,0)            AS PostsReopened,

    -- Recent activity as JSON array (ordered by date desc)
    (
        SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'Type', ra.Type,
                    'Id',   ra.PostId,
                    'TitleOrText', ra.Title,
                    'Created', ra.CreationDate
                )
                ORDER BY ra.CreationDate DESC
            )
        FROM   recent_activity ra
        WHERE  ra.UserId = bu.UserId
    )                                        AS RecentActivity
FROM   base_users        bu
LEFT   JOIN post_stats      ps ON ps.UserId = bu.UserId
LEFT   JOIN vote_stats      vs ON vs.UserId = bu.UserId
LEFT   JOIN badge_summary   bs ON bs.UserId = bu.UserId
LEFT   JOIN tag_participation tp ON tp.UserId = bu.UserId
LEFT   JOIN closure_stats   cs ON cs.UserId = bu.UserId
ORDER  BY bu.Reputation DESC
LIMIT  100;
