-- {"query": "1538.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2716} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(c.CreationDate) AS FirstCommentDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        (u.UpVotes - u.DownVotes) AS NetVotesGiven,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / 3600 / 24 AS AccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes
    HAVING COUNT(DISTINCT p.Id) > 5 AND u.Reputation > 100
),
PostInteractionMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.LastActivityDate,
        COALESCE(p.LastEditDate, p.CreationDate) AS EffectiveLastEditDate,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId, p.PostTypeId) AS AvgScoreForUserPostType,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostTypeRank,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
        CASE
            WHEN p.Title IS NULL THEN 'No Title'
            WHEN LENGTH(p.Title) > 50 THEN SUBSTRING(p.Title, 1, 47) || '...'
            ELSE p.Title
        END AS ShortTitle,
        (SELECT MAX(s.Score) FROM Comments s WHERE s.PostId = p.Id AND s.UserId = p.OwnerUserId) AS MaxOwnerCommentScore -- Correlated subquery
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions or Answers
),
PostLifecycleEvents AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EventDate,
        ph.UserId AS EventUserId,
        cr.Name AS CloseReasonName,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate,
        LEAD(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextEventDate,
        ph.Text AS EventDetails
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON ph.PostHistoryTypeId = 10 AND ph.Comment = cr.Id::text
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20) -- Post Closed, Reopened, Deleted, Undeleted, Protected, Unprotected
),
BadgeAchievements AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeAwardDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn_latest_badge
    FROM Badges b
    WHERE b.Class IN (1,2) -- Gold or Silver badges
),
RankedComments AS (
    SELECT
        c.PostId,
        c.UserId AS CommenterId,
        c.Score AS CommentScore,
        c.CreationDate AS CommentDate,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate DESC) AS rn_comment
    FROM Comments c
    WHERE c.Score > 0
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(pl.RelatedPostId) AS TotalRelatedLinks,
        SUM(CASE WHEN plt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinks,
        MAX(pl.CreationDate) AS LastLinkDate,
        (SELECT p_rel.Score FROM Posts p_rel WHERE p_rel.Id = MIN(pl.RelatedPostId)) AS FirstRelatedPostScore -- Correlated subquery example
    FROM PostLinks pl
    JOIN LinkTypes plt ON pl.LinkTypeId = plt.Id
    GROUP BY pl.PostId
)
-- Main Query starts here
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    pim.PostId,
    pim.PostTypeId,
    pim.ShortTitle,
    pim.PostScore,
    pim.ViewCount,
    pim.AnswerCount,
    pim.CommentCount AS PostCommentCount,
    pim.FavoriteCount,
    pim.TagArray,
    uas.TotalPosts,
    uas.TotalComments,
    uas.AvgPostScore,
    uas.AccountAgeDays,
    pim.PreviousPostScore,
    pim.AvgScoreForUserPostType,
    pim.PostTypeRank,
    pim.MaxOwnerCommentScore,
    COALESCE(ph_closed.EventDate, ph_deleted.EventDate, '1900-01-01'::timestamp) AS LastMajorEventDate,
    ph_closed.CloseReasonName,
    COALESCE(EXTRACT(EPOCH FROM (ph_closed.NextEventDate - ph_closed.EventDate)) / 3600, 0) AS HoursUntilReopened,
    ba.BadgeName AS LatestGoldSilverBadge,
    rc.CommentScore AS TopCommentScoreOnPost,
    pls.TotalRelatedLinks,
    pls.DuplicateLinks,
    (uas.Reputation * pim.PostScore / NULLIF(pim.ViewCount + 1, 0)) AS ImpactScore,
    CASE
        WHEN uas.AccountAgeDays < 365 THEN 'New User (<1yr)'
        WHEN uas.AccountAgeDays BETWEEN 365 AND 1825 THEN 'Active User (1-5yrs)'
        ELSE 'Veteran User (>5yrs)'
    END AS UserAgeCategory,
    NULLIF(pim.PostScore, 0) * (SELECT COUNT(DISTINCT q.Id) FROM Posts q WHERE q.ParentId = pim.PostId AND q.PostTypeId = 2) AS DerivedAnswerValue
FROM UserActivitySummary uas
JOIN PostInteractionMetrics pim ON uas.UserId = pim.OwnerUserId
LEFT JOIN PostLifecycleEvents ph_closed ON pim.PostId = ph_closed.PostId AND ph_closed.PostHistoryTypeId = 10
LEFT JOIN PostLifecycleEvents ph_reopened ON pim.PostId = ph_reopened.PostId AND ph_reopened.PostHistoryTypeId = 11
LEFT JOIN PostLifecycleEvents ph_deleted ON pim.PostId = ph_deleted.PostId AND ph_deleted.PostHistoryTypeId = 12
LEFT JOIN BadgeAchievements ba ON uas.UserId = ba.UserId AND ba.rn_latest_badge = 1
LEFT JOIN RankedComments rc ON pim.PostId = rc.PostId AND rc.rn_comment = 1
LEFT JOIN PostLinkSummary pls ON pim.PostId = pls.PostId
WHERE
    (pim.PostTypeId = 1 AND pim.AnswerCount > 0) OR (pim.PostTypeId = 2 AND pim.PostScore > 50)
    AND (EXISTS (SELECT 1 FROM Tags t WHERE t.TagName = ANY(pim.TagArray) AND t.Count > 1000) OR pim.FavoriteCount > 10)
    AND pim.EffectiveLastEditDate > (CURRENT_TIMESTAMP - INTERVAL '2 year')
    AND ph_closed.CloseReasonName IS DISTINCT FROM 'Duplicate'
    AND pim.Title IS NOT NULL

UNION ALL

SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    p.Id AS PostId,
    p.PostTypeId,
    p.Title AS ShortTitle,
    p.Score AS PostScore,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount AS PostCommentCount,
    p.FavoriteCount,
    STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
    (SELECT COUNT(DISTINCT p_sub.Id) FROM Posts p_sub WHERE p_sub.OwnerUserId = u.Id) AS TotalPosts,
    (SELECT COUNT(DISTINCT c_sub.Id) FROM Comments c_sub WHERE c_sub.UserId = u.Id) AS TotalComments,
    (SELECT AVG(p_sub.Score) FROM Posts p_sub WHERE p_sub.OwnerUserId = u.Id AND p_sub.PostTypeId IN (1,2)) AS AvgPostScore,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / 3600 / 24 AS AccountAgeDays,
    NULL::int AS PreviousPostScore,
    NULL::numeric AS AvgScoreForUserPostType,
    NULL::bigint AS PostTypeRank,
    (SELECT MAX(s.Score) FROM Comments s WHERE s.PostId = p.Id AND s.UserId = p.OwnerUserId) AS MaxOwnerCommentScore,
    '1900-01-01 00:00:00'::timestamp AS LastMajorEventDate,
    NULL::varchar(50) AS CloseReasonName,
    0::numeric AS HoursUntilReopened,
    NULL::varchar(50) AS LatestGoldSilverBadge,
    NULL::int AS TopCommentScoreOnPost,
    NULL::bigint AS TotalRelatedLinks,
    NULL::bigint AS DuplicateLinks,
    (u.Reputation * p.Score / NULLIF(p.ViewCount + 1, 0)) AS ImpactScore,
    'New Questions Focus' AS UserAgeCategory,
    NULLIF(p.Score, 0) * (SELECT COUNT(DISTINCT q.Id) FROM Posts q WHERE q.ParentId = p.Id AND q.PostTypeId = 2) AS DerivedAnswerValue
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
WHERE
    u.Reputation BETWEEN 500 AND 5000
    AND p.PostTypeId = 1
    AND p.ViewCount > 5000
    AND p.AnswerCount IS NULL
    AND p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
ORDER BY ImpactScore DESC, LastMajorEventDate DESC, UserId, PostId
LIMIT 1000;
