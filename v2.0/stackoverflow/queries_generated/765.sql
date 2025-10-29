-- {"query": "765.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3822} 
WITH recent_active_users AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        COALESCE(NULLIF(TRIM(u.WebsiteUrl), ''), 'N/A') AS WebsiteNorm
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.LastAccessDate >= NOW() - INTERVAL '365 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.UpVotes, u.DownVotes, u.Views, u.WebsiteUrl
),
user_post_activity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS Questions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS Answers,
        COUNT(*) FILTER (WHERE p.Score > 0) AS PositivePosts,
        COUNT(*) FILTER (WHERE p.Score < 0) AS NegativePosts,
        COUNT(*) FILTER (WHERE p.ClosedDate IS NOT NULL) AS ClosedQuestions,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        AVG(NULLIF(p.Score, 0)) AS AvgNonZeroScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        COUNT(*) FILTER (WHERE p.CommunityOwnedDate IS NOT NULL) AS CommunityOwnedPosts
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
question_tag_explode AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND length(p.Tags) > 2
),
user_top_tags AS (
    SELECT
        q.UserId,
        t.TagName,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY q.UserId ORDER BY COUNT(*) DESC, t.TagName) AS rn
    FROM question_tag_explode q
    JOIN Tags t ON LOWER(t.TagName) = LOWER(q.TagName)
    GROUP BY q.UserId, t.TagName
),
user_top3_tags AS (
    SELECT UserId,
           array_agg(TagName ORDER BY rn) FILTER (WHERE rn <= 3) AS TopTags
    FROM user_top_tags
    WHERE rn <= 3
    GROUP BY UserId
),
vote_agg AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesReceived,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesReceived,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 8) AS BountiesStarted,
        COALESCE(SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId IN (8,9)), 0) AS BountyAmountTotal,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2,3) THEN v.Id END) AS TotalVotesOnPosts
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
comment_agg AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
close_events AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS ClosedAt,
        CAST(NULLIF(ph.Comment, '') AS integer) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10) -- Post Closed
),
duplicate_links AS (
    SELECT
        pl.PostId AS DuplicateOfPostId,
        COUNT(*) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
accepted_answerers AS (
    SELECT
        a.OwnerUserId AS UserId,
        COUNT(*) AS AcceptedAnswers
    FROM Posts q
    JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1 AND a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),
activity_window AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS PostId,
        p.CreationDate,
        p.Score,
        SUM(COALESCE(p.Score,0)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_recent
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
user_recent_posts AS (
    SELECT
        aw.UserId,
        COUNT(*) FILTER (WHERE aw.rn_recent <= 10) AS Last10Posts,
        MAX(CASE WHEN aw.rn_recent = 1 THEN aw.PostId END) AS MostRecentPostId,
        MAX(CASE WHEN aw.rn_recent = 1 THEN aw.CreationDate END) AS MostRecentPostDate,
        MAX(CASE WHEN aw.rn_recent = 1 THEN aw.Score END) AS MostRecentPostScore
    FROM activity_window aw
    GROUP BY aw.UserId
),
user_quality_score AS (
    SELECT
        u.Id AS UserId,
        /* Mixed metrics with NULL logic and conditional weighting */
        (
            0.40 * COALESCE(ua.Answers::numeric / NULLIF(ua.Questions,0), 0) +
            0.25 * COALESCE(va.UpvotesReceived::numeric / NULLIF(GREATEST(va.UpvotesReceived + va.DownvotesReceived, 0), 0), 0) +
            0.20 * COALESCE(ad.AcceptedAnswers::numeric / NULLIF(ua.Answers,0), 0) +
            0.15 * COALESCE(ua.AvgNonZeroScore, 0)
        ) AS CompositeQuality
    FROM Users u
    LEFT JOIN user_post_activity ua ON ua.UserId = u.Id
    LEFT JOIN vote_agg va ON va.UserId = u.Id
    LEFT JOIN accepted_answerers ad ON ad.UserId = u.Id
),
closed_reason_breakdown AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE cr.CloseReasonId = 101) AS ClosedDuplicate,
        COUNT(*) FILTER (WHERE cr.CloseReasonId = 102) AS ClosedOffTopic,
        COUNT(*) FILTER (WHERE cr.CloseReasonId = 103) AS ClosedNeedsDetails,
        COUNT(*) FILTER (WHERE cr.CloseReasonId = 104) AS ClosedNeedsFocus,
        COUNT(*) FILTER (WHERE cr.CloseReasonId = 105) AS ClosedOpinionBased,
        COUNT(*) FILTER (WHERE cr.CloseReasonId IS NULL) AS ClosedUnspecified
    FROM Posts p
    LEFT JOIN close_events cr ON cr.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
website_domain AS (
    SELECT
        rau.UserId,
        LOWER(
            REGEXP_REPLACE(
                REGEXP_REPLACE(COALESCE(rau.WebsiteNorm,''), '^https?://', '', 'i'),
                '/.*$', ''
            )
        ) AS Domain
    FROM recent_active_users rau
),
domain_rank AS (
    SELECT
        wd.Domain,
        COUNT(*) AS UserCount,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC NULLS LAST) AS DomainRank
    FROM website_domain wd
    WHERE wd.Domain IS NOT NULL AND wd.Domain <> '' AND wd.Domain NOT LIKE '%stackexchange%'
    GROUP BY wd.Domain
),
user_domain_rank AS (
    SELECT
        wd.UserId,
        dr.Domain,
        dr.DomainRank
    FROM website_domain wd
    LEFT JOIN domain_rank dr ON dr.Domain = wd.Domain
),
high_view_questions AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1 AND p.ViewCount >= 10000) AS Q10kViews
    FROM Posts p
    GROUP BY p.OwnerUserId
),
hotness_bumps AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (50,52)) AS HotOrBumped
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    GROUP BY p.OwnerUserId
),
combined_users AS (
    SELECT DISTINCT u.Id AS UserId
    FROM Users u
    WHERE u.LastAccessDate >= NOW() - INTERVAL '365 days'
),
final_scores AS (
    SELECT
        cu.UserId,
        rau.DisplayName,
        rau.Reputation,
        ua.Questions,
        ua.Answers,
        ua.PositivePosts,
        ua.NegativePosts,
        ua.ClosedQuestions,
        ua.TotalPosts,
        ua.TotalViews,
        ua.AvgNonZeroScore,
        ua.LastPostActivity,
        ua.CommunityOwnedPosts,
        va.UpvotesReceived,
        va.DownvotesReceived,
        va.BountiesStarted,
        va.BountyAmountTotal,
        va.TotalVotesOnPosts,
        ca.CommentCount,
        ca.AvgCommentScore,
        ca.LastCommentDate,
        dq.DuplicateCount,
        ad.AcceptedAnswers,
        urp.Last10Posts,
        urp.MostRecentPostId,
        urp.MostRecentPostDate,
        urp.MostRecentPostScore,
        ut3.TopTags,
        crb.ClosedDuplicate,
        crb.ClosedOffTopic,
        crb.ClosedNeedsDetails,
        crb.ClosedNeedsFocus,
        crb.ClosedOpinionBased,
        crb.ClosedUnspecified,
        rau.GoldBadges,
        rau.SilverBadges,
        rau.BronzeBadges,
        rau.TotalBadges,
        COALESCE(udr.Domain, 'unknown') AS WebsiteDomain,
        udr.DomainRank,
        hvq.Q10kViews,
        hb.HotOrBumped,
        uq.CompositeQuality,
        /* String expressions and NULL-safe concatenation */
        TRIM(
          BOTH ' ' FROM
          COALESCE(rau.DisplayName, '') || ' #' || COALESCE(rau.Reputation::varchar, '0')
        ) AS DisplayWithRep,
        /* Complex predicate as normalized flags */
        CASE
            WHEN COALESCE(ua.Answers,0) > COALESCE(ua.Questions,0) AND COALESCE(va.UpvotesReceived,0) >= 10 THEN 'Answerer'
            WHEN COALESCE(ua.Questions,0) >= 5 AND COALESCE(crb.ClosedDuplicate,0) / NULLIF(COALESCE(ua.Questions,0),0) > 0.25 THEN 'NeedsTagGuidance'
            WHEN COALESCE(hvq.Q10kViews,0) >= 5 THEN 'PopularAsker'
            ELSE 'Generalist'
        END AS UserArchetype
    FROM combined_users cu
    LEFT JOIN recent_active_users rau ON rau.UserId = cu.UserId
    LEFT JOIN user_post_activity ua ON ua.UserId = cu.UserId
    LEFT JOIN vote_agg va ON va.UserId = cu.UserId
    LEFT JOIN comment_agg ca ON ca.UserId = cu.UserId
    LEFT JOIN duplicate_links dq ON dq.DuplicateOfPostId = COALESCE(NULLIF(ua.TotalPosts,0), -1) -- intentionally skewed join to add outer join pressure
    LEFT JOIN accepted_answerers ad ON ad.UserId = cu.UserId
    LEFT JOIN user_recent_posts urp ON urp.UserId = cu.UserId
    LEFT JOIN user_top3_tags ut3 ON ut3.UserId = cu.UserId
    LEFT JOIN closed_reason_breakdown crb ON crb.UserId = cu.UserId
    LEFT JOIN user_domain_rank udr ON udr.UserId = cu.UserId
    LEFT JOIN high_view_questions hvq ON hvq.UserId = cu.UserId
    LEFT JOIN hotness_bumps hb ON hb.UserId = cu.UserId
    LEFT JOIN user_quality_score uq ON uq.UserId = cu.UserId
),
ranked AS (
    SELECT
        fs.*,
        /* Window functions for ranking and percentiles */
        ROW_NUMBER() OVER (ORDER BY COALESCE(fs.CompositeQuality,0) DESC, COALESCE(fs.Reputation,0) DESC) AS rn,
        RANK() OVER (ORDER BY COALESCE(fs.Reputation,0) DESC) AS rep_rank,
        DENSE_RANK() OVER (ORDER BY COALESCE(fs.TotalVotesOnPosts,0) DESC) AS vote_dense_rank,
        PERCENT_RANK() OVER (ORDER BY COALESCE(fs.AvgNonZeroScore,0)) AS avg_score_pct,
        NTILE(10) OVER (ORDER BY COALESCE(fs.CompositeQuality,0) DESC) AS quality_decile
    FROM final_scores fs
),
aggregate_tail AS (
    SELECT
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.CompositeQuality,
        r.quality_decile,
        r.rep_rank,
        r.vote_dense_rank,
        r.avg_score_pct,
        r.UserArchetype,
        r.TopTags,
        r.WebsiteDomain,
        r.DomainRank,
        r.GoldBadges, r.SilverBadges, r.BronzeBadges, r.TotalBadges,
        r.Answers, r.Questions, r.AcceptedAnswers,
        r.UpvotesReceived, r.DownvotesReceived,
        r.Q10kViews, r.HotOrBumped,
        r.ClosedDuplicate, r.ClosedOffTopic, r.ClosedNeedsDetails, r.ClosedNeedsFocus, r.ClosedOpinionBased, r.ClosedUnspecified,
        /* Correlated subquery: most commented post id for each user (by score, then recency) */
        (
          SELECT p.Id
          FROM Posts p
          LEFT JOIN Comments c ON c.PostId = p.Id
          WHERE p.OwnerUserId = r.UserId
          GROUP BY p.Id, p.CreationDate
          ORDER BY COUNT(c.Id) DESC, COALESCE(p.Score,0) DESC, p.CreationDate DESC
          LIMIT 1
        ) AS MostCommentedPostId,
        /* Set operator: intersect of user's top tag set with globally top tags */
        (
          SELECT array_agg(tagname)
          FROM (
            SELECT tagname FROM unnest(COALESCE(r.TopTags, ARRAY[]::varchar[])) AS tagname
            INTERSECT
            SELECT t.TagName FROM Tags t ORDER BY t.Count DESC LIMIT 10
          ) z
        ) AS OverlapWithTopTags
    FROM ranked r
)
SELECT
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.CompositeQuality,
    a.quality_decile,
    a.rep_rank,
    a.vote_dense_rank,
    a.avg_score_pct,
    a.UserArchetype,
    a.TopTags,
    a.OverlapWithTopTags,
    a.WebsiteDomain,
    a.DomainRank,
    a.GoldBadges, a.SilverBadges, a.BronzeBadges, a.TotalBadges,
    a.Answers, a.Questions, a.AcceptedAnswers,
    a.UpvotesReceived, a.DownvotesReceived,
    a.Q10kViews, a.HotOrBumped,
    a.ClosedDuplicate, a.ClosedOffTopic, a.ClosedNeedsDetails, a.ClosedNeedsFocus, a.ClosedOpinionBased, a.ClosedUnspecified,
    a.MostCommentedPostId,
    /* Complicated predicate/expressions with null logic */
    CASE
        WHEN COALESCE(a.CompositeQuality,0) > 1.5 AND COALESCE(a.AcceptedAnswers,0) >= 50 THEN 'elite'
        WHEN a.quality_decile <= 2 AND COALESCE(a.Reputation,0) > 5000 THEN 'high-performer'
        WHEN a.quality_decile BETWEEN 3 AND 7 THEN 'mid-tier'
        ELSE 'emerging'
    END AS Cohort
FROM aggregate_tail a
WHERE
    /* mix of string, numeric, null logic filters */
    (a.DisplayName IS NOT NULL AND LENGTH(TRIM(a.DisplayName)) >= 3)
    AND COALESCE(a.TotalBadges, 0) + COALESCE(a.AcceptedAnswers, 0) + COALESCE(a.Q10kViews, 0) > 0
    AND NOT (a.WebsiteDomain ILIKE '%spam%' OR a.WebsiteDomain ILIKE '%.ru')
    AND (a.ClosedOffTopic IS NULL OR a.ClosedOffTopic < COALESCE(a.Questions,0) / 2)
ORDER BY
    a.quality_decile ASC,
    a.CompositeQuality DESC NULLS LAST,
    a.Reputation DESC NULLS LAST
LIMIT 200;