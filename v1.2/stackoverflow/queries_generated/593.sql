-- {"query": "593.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1760} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
  UNION ALL
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id <> ALL(r.TagPath::text[])
    WHERE t.IsRequired = 1
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(u.AboutMe, '') AS AboutMe,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS UserRank
    FROM Users u
    WHERE u.Reputation > 1000 AND u.Location IS NOT NULL
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY b.UserId, b.Class
),
UserActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgPostViews,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(p.LastActivityDate) AS LastActivity
    FROM Posts p
    LEFT JOIN Comments c ON c.UserId = p.OwnerUserId
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > CURRENT_DATE - INTERVAL '2 years'
    GROUP BY p.OwnerUserId
),
QuestionAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreation,
        a.ParentId,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
CloseReasonSummary AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseVotesCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS smallint)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, crt.Name
),
UserVoteStats AS (
    SELECT
        v.UserId,
        vt.Name AS VoteType,
        COUNT(*) AS VoteCount,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty
    FROM Votes v
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId, vt.Name
),
ComplexUserSummary AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges,
        COALESCE(ua.PostCount, 0) AS Posts,
        COALESCE(ua.CommentCount, 0) AS Comments,
        COALESCE(ua.TotalPostScore, 0) AS PostScoreSum,
        COALESCE(uvs_up.VoteCount, 0) AS UpVotesGiven,
        COALESCE(uvs_down.VoteCount, 0) AS DownVotesGiven,
        COALESCE(uvs_bounty.TotalBounty, 0) AS BountyGiven
    FROM TopUsers u
    LEFT JOIN UserBadgeCounts ubc_gold ON ubc_gold.UserId = u.Id AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON ubc_silver.UserId = u.Id AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON ubc_bronze.UserId = u.Id AND ubc_bronze.Class = 3
    LEFT JOIN UserActivity ua ON ua.UserId = u.Id
    LEFT JOIN UserVoteStats uvs_up ON uvs_up.UserId = u.Id AND uvs_up.VoteType = 'UpMod'
    LEFT JOIN UserVoteStats uvs_down ON uvs_down.UserId = u.Id AND uvs_down.VoteType = 'DownMod'
    LEFT JOIN UserVoteStats uvs_bounty ON uvs_bounty.UserId = u.Id AND uvs_bounty.VoteType = 'BountyStart'
),
FinalAnswerStats AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.QuestionCreation,
        q.QuestionScore,
        q.QuestionViews,
        q.AnswerId,
        q.AnswerUserId,
        q.AnswerScore,
        q.AnswerCreation,
        q.AnswerRank,
        u.DisplayName AS AnswerUserName,
        u.Reputation AS AnswerUserReputation,
        cr.CloseReason,
        cr.CloseVotesCount
    FROM QuestionAnswerStats q
    LEFT JOIN Users u ON u.Id = q.AnswerUserId
    LEFT JOIN CloseReasonSummary cr ON cr.PostId = q.QuestionId
    WHERE q.AnswerRank <= 3 OR q.AnswerId IS NULL
),
StringAnalysis AS (
    SELECT
        p.Id,
        p.Title,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(REGEXP_REPLACE(p.Body, '[^a-zA-Z]', '', 'g')) AS AlphaChars,
        LENGTH(REGEXP_REPLACE(p.Body, '[^0-9]', '', 'g')) AS NumericChars,
        COALESCE(NULLIF(p.Tags, ''), '<none>') AS TagString,
        STRING_AGG(DISTINCT COALESCE(b.Name, '')) FILTER (WHERE b.UserId = p.OwnerUserId) AS UserBadges,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Body, p.Tags, p.ClosedDate
)
SELECT
    fs.QuestionId,
    fs.Title AS QuestionTitle,
    fs.QuestionCreation,
    fs.QuestionScore,
    fs.QuestionViews,
    fs.AnswerId,
    fs.AnswerUserName,
    fs.AnswerUserReputation,
    fs.AnswerScore,
    fs.AnswerCreation,
    fs.AnswerRank,
    fs.CloseReason,
    fs.CloseVotesCount,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.Posts AS UserPosts,
    cus.Comments AS UserComments,
    cus.PostScoreSum,
    cus.UpVotesGiven,
    cus.DownVotesGiven,
    cus.BountyGiven,
    sa.BodyLength,
    sa.AlphaChars,
    sa.NumericChars,
    sa.TagString,
    sa.UserBadges,
    sa.PostStatus,
    rh.TagPath
FROM FinalAnswerStats fs
LEFT JOIN ComplexUserSummary cus ON cus.Id = fs.AnswerUserId
LEFT JOIN StringAnalysis sa ON sa.Id = fs.QuestionId
LEFT JOIN RecursiveTagHierarchy rh ON rh.TagName = (SELECT unnest(string_to_array(sa.TagString, '><')) LIMIT 1)
WHERE fs.QuestionCreation > CURRENT_DATE - INTERVAL '1 year'
  AND (fs.AnswerScore IS NULL OR fs.AnswerScore >= 5)
ORDER BY fs.QuestionScore DESC, fs.AnswerScore DESC NULLS LAST, cus.Reputation DESC
LIMIT 100;
