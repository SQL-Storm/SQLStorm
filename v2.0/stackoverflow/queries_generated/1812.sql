-- {"query": "1812.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3884} 

WITH UserInfluence AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE b.Class WHEN 1 THEN 30 WHEN 2 THEN 10 WHEN 3 THEN 1 ELSE 0 END) AS BadgeScore, -- Gold badges weigh heavily
        AVG(u.Reputation) OVER () AS AvgUserReputation,
        RANK() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, COUNT(b.Id) DESC) AS UserOverallRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
PostVersionHistory AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_desc,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC) AS rn_asc
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9) -- Initial, Edit, Rollback for Title/Body/Tags
),
PostEditMetrics AS (
    SELECT
        pvh.PostId,
        COUNT(DISTINCT pvh.HistoryDate) AS TotalHistoryEvents,
        COUNT(CASE WHEN pvh.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS TotalEdits, -- Only actual edits
        EXTRACT(EPOCH FROM (MAX(pvh.HistoryDate) - MIN(pvh.HistoryDate))) / (60 * 60 * 24) AS DaysSinceFirstHistory,
        COALESCE(AVG(NULLIF(EXTRACT(EPOCH FROM (pvh.HistoryDate - pvh.PreviousHistoryDate)), 0)), 0) AS AvgEventIntervalSeconds, -- Avoid division by zero
        MAX(CASE WHEN pvh.rn_desc = 1 THEN pvh.HistoryDate ELSE NULL END) AS LatestHistoryDate,
        MIN(CASE WHEN pvh.rn_asc = 1 THEN pvh.HistoryDate ELSE NULL END) AS EarliestHistoryDate
    FROM PostVersionHistory pvh
    GROUP BY pvh.PostId
),
QuestionEngagementStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COUNT(DISTINCT v_up.Id) AS UpVoteCount,
        COUNT(DISTINCT v_down.Id) AS DownVoteCount,
        COALESCE(p.FavoriteCount, 0) AS ActualFavoriteCount,
        (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) AS LatestCommentCreationDate, -- Correlated subquery
        STRING_AGG(DISTINCT t.TagName, ';') FILTER (WHERE t.TagName IS NOT NULL) AS AssociatedTagsString,
        SUM(CASE WHEN pl_in.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedFromCount, -- Others link to this
        SUM(CASE WHEN pl_in.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateFromCount, -- Others are duplicates of this
        SUM(CASE WHEN pl_out.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedToCount, -- This links to others
        SUM(CASE WHEN pl_out.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateToCount -- This is a duplicate of others
    FROM Posts p
    LEFT JOIN Votes v_up ON p.Id = v_up.PostId AND v_up.VoteTypeId = 2 -- UpMod
    LEFT JOIN Votes v_down ON p.Id = v_down.PostId AND v_down.VoteTypeId = 3 -- DownMod
    LEFT JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%' -- Match tags
    LEFT JOIN PostLinks pl_in ON p.Id = pl_in.RelatedPostId -- Incoming links
    LEFT JOIN PostLinks pl_out ON p.Id = pl_out.PostId -- Outgoing links
    WHERE p.PostTypeId = 1 -- Only Questions
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.AcceptedAnswerId, p.Score, p.ViewCount, p.CreationDate,
             p.LastActivityDate, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount,
             p.ClosedDate, p.CommunityOwnedDate
),
CombinedQuestionMetrics AS (
    SELECT
        qes.PostId,
        qes.Title,
        qes.CreationDate,
        qes.LastActivityDate,
        qes.OwnerUserId,
        ui.DisplayName AS OwnerDisplayName,
        ui.Reputation AS OwnerReputation,
        ui.BadgeScore AS OwnerBadgeScore,
        ui.UserOverallRank AS OwnerRank,
        qes.Score,
        qes.ViewCount,
        qes.AnswerCount,
        qes.CommentCount,
        qes.ActualFavoriteCount,
        qes.UpVoteCount,
        qes.DownVoteCount,
        qes.LatestCommentCreationDate,
        qes.AssociatedTagsString,
        qes.LinkedFromCount,
        qes.DuplicateFromCount,
        qes.LinkedToCount,
        qes.DuplicateToCount,
        pem.TotalEdits,
        pem.DaysSinceFirstHistory,
        pem.AvgEventIntervalSeconds,
        pem.LatestHistoryDate,
        pem.EarliestHistoryDate,
        qes.ClosedDate,
        qes.AcceptedAnswerId,
        qes.CommunityOwnedDate,
        -- Complex Post Engagement Calculation
        (qes.Score * 0.7 + qes.UpVoteCount * 0.5 - qes.DownVoteCount * 0.3 + qes.CommentCount * 0.2 + qes.AnswerCount * 0.6 + qes.ActualFavoriteCount * 1.0 + qes.ViewCount / 100.0) AS RawEngagementScore,
        -- Time decay factor: newer posts get a boost
        EXP(-EXTRACT(EPOCH FROM (NOW() - qes.LastActivityDate)) / (60 * 60 * 24 * 365.0)) AS ActivityDecayFactor, -- Exponential decay over years
        CASE
            WHEN qes.AcceptedAnswerId IS NOT NULL AND qes.ClosedDate IS NULL THEN 'Solved_Open'
            WHEN qes.AcceptedAnswerId IS NULL AND qes.ClosedDate IS NULL THEN 'Unsolved_Open'
            WHEN qes.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN qes.CommunityOwnedDate IS NOT NULL THEN 'Community_Owned'
            ELSE 'Other'
        END AS QuestionState,
        LENGTH(TRIM(COALESCE(qes.Title, ''))) AS TitleLength, -- String expression with TRIM and COALESCE
        REPLACE(REPLACE(UPPER(COALESCE(qes.Title, '')), 'SQL', 'DATABASE'), 'POSTGRES', 'RELATIONAL_DB') AS TransformedTitleSegment -- String manipulation
    FROM QuestionEngagementStats qes
    LEFT JOIN UserInfluence ui ON qes.OwnerUserId = ui.UserId
    LEFT JOIN PostEditMetrics pem ON qes.PostId = pem.PostId
),
FinalRanking AS (
    SELECT
        cqm.PostId,
        cqm.Title,
        cqm.OwnerDisplayName,
        cqm.OwnerReputation,
        cqm.CreationDate,
        cqm.LastActivityDate,
        cqm.TotalEdits,
        cqm.AssociatedTagsString,
        cqm.LinkedFromCount,
        cqm.DuplicateFromCount,
        cqm.LinkedToCount,
        cqm.DuplicateToCount,
        cqm.RawEngagementScore,
        cqm.ActivityDecayFactor,
        cqm.QuestionState,
        cqm.TitleLength,
        cqm.TransformedTitleSegment,
        -- Overall Influence Score
        (cqm.RawEngagementScore * cqm.ActivityDecayFactor * 2.0 + cqm.OwnerReputation / 1000.0 * cqm.OwnerBadgeScore + cqm.TotalEdits * 5 + cqm.LinkedFromCount * 10) AS OverallInfluenceScore,
        ROW_NUMBER() OVER (ORDER BY (cqm.RawEngagementScore * cqm.ActivityDecayFactor * 2.0 + cqm.OwnerReputation / 1000.0 * cqm.OwnerBadgeScore + cqm.TotalEdits * 5 + cqm.LinkedFromCount * 10) DESC, cqm.CreationDate ASC) AS OverallRank,
        NTILE(5) OVER (ORDER BY (cqm.RawEngagementScore * cqm.ActivityDecayFactor * 2.0 + cqm.OwnerReputation / 1000.0 * cqm.OwnerBadgeScore + cqm.TotalEdits * 5 + cqm.LinkedFromCount * 10) DESC) AS InfluenceQuintile,
        RANK() OVER (PARTITION BY cqm.QuestionState ORDER BY cqm.RawEngagementScore DESC) AS RankWithinState,
        LAG(cqm.Title, 1, 'N/A') OVER (PARTITION BY cqm.OwnerUserId ORDER BY cqm.CreationDate) AS PreviousQuestionTitleByOwner -- LAG function
    FROM CombinedQuestionMetrics cqm
    WHERE
        cqm.OwnerReputation > (SELECT AVG(Reputation) FROM Users) -- Subquery for filtering
        AND cqm.ViewCount > 5000 -- High view count
        AND cqm.TotalEdits > 2 -- Edited at least 3 times
        AND cqm.DaysSinceFirstHistory IS NOT NULL AND cqm.DaysSinceFirstHistory > 10 -- Active for more than 10 days
        AND POSITION('PERFORMANCE' IN cqm.TransformedTitleSegment) > 0 -- String expression
        AND NOT EXISTS (
            SELECT 1 FROM PostHistory ph_closed WHERE ph_closed.PostId = cqm.PostId AND ph_closed.PostHistoryTypeId = 10 AND ph_closed.CreationDate > NOW() - INTERVAL '1 year'
        ) -- Correlated NOT EXISTS for recently closed posts
        AND (cqm.ClosedDate IS NULL OR cqm.ClosedDate > NOW() - INTERVAL '6 months') -- Not very old closed posts, or still open
),
SuperContributors AS (
    SELECT UserId FROM UserInfluence WHERE UserOverallRank <= 50 AND BadgeScore >= 100
),
TopImpactfulAnswers AS (
    SELECT
        p.Id AS PostId,
        p.Title AS Title,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        p.CreationDate,
        p.LastActivityDate,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS TotalEdits,
        STRING_AGG(DISTINCT t.TagName, ';') FILTER (WHERE t.TagName IS NOT NULL) AS AssociatedTagsString,
        0 AS LinkedFromCount,
        0 AS DuplicateFromCount,
        0 AS LinkedToCount,
        0 AS DuplicateToCount,
        (p.Score * 1.5 + COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) * 1.0) AS RawEngagementScore,
        EXP(-EXTRACT(EPOCH FROM (NOW() - p.LastActivityDate)) / (60 * 60 * 24 * 365.0)) AS ActivityDecayFactor,
        'Answer' AS QuestionState,
        LENGTH(TRIM(COALESCE(p.Title, ''))) AS TitleLength,
        REPLACE(REPLACE(UPPER(COALESCE(p.Title, '')), 'SQL', 'DATABASE'), 'PERFORMANCE', 'OPTIMIZATION') AS TransformedTitleSegment,
        (p.Score * 2.0 + COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) * 1.5 + u.Reputation / 500.0) AS OverallInfluenceScore,
        NULL::bigint AS OverallRank,
        NULL::int AS InfluenceQuintile,
        NULL::bigint AS RankWithinState,
        NULL::varchar(300) AS PreviousQuestionTitleByOwner
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    INNER JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
    LEFT JOIN Tags t ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IN (SELECT UserId FROM SuperContributors)
      AND p.Score > 20
      AND p.ParentId IN (SELECT PostId FROM FinalRanking) -- Answers to already influential questions
    GROUP BY p.Id, p.Title, u.DisplayName, u.Reputation, p.CreationDate, p.LastActivityDate, p.Score, p.CommunityOwnedDate
)
SELECT
    'Question' AS PostType,
    fr.PostId,
    fr.Title,
    fr.OwnerDisplayName,
    fr.OwnerReputation,
    fr.CreationDate,
    fr.LastActivityDate,
    fr.TotalEdits,
    fr.AssociatedTagsString,
    fr.LinkedFromCount,
    fr.DuplicateFromCount,
    fr.LinkedToCount,
    fr.DuplicateToCount,
    fr.RawEngagementScore,
    fr.ActivityDecayFactor,
    fr.QuestionState,
    fr.TitleLength,
    fr.TransformedTitleSegment,
    fr.OverallInfluenceScore,
    fr.OverallRank,
    fr.InfluenceQuintile,
    fr.RankWithinState,
    fr.PreviousQuestionTitleByOwner,
    CASE
        WHEN fr.OverallRank <= 10 THEN 'Top 10 Global Elite'
        WHEN fr.InfluenceQuintile = 1 THEN 'Top 20% Influencer'
        WHEN fr.RankWithinState = 1 AND fr.QuestionState = 'Solved_Open' THEN 'Best Solved Open Question'
        WHEN fr.OwnerReputation > 50000 THEN 'By Veteran User'
        ELSE 'General Influential'
    END AS InfluenceCategory,
    COALESCE(fr.RawEngagementScore / NULLIF(fr.TotalEdits, 0), 0.0) AS EngagementPerEdit
FROM FinalRanking fr
WHERE fr.OverallRank <= 500
  AND fr.OwnerReputation >= (SELECT MAX(Reputation) * 0.1 FROM Users)
  AND fr.PostId NOT IN (SELECT PostId FROM PostHistory WHERE PostHistoryTypeId = 12)
  AND fr.LinkedFromCount > 0
UNION ALL
SELECT
    'Answer' AS PostType,
    tia.PostId,
    tia.Title,
    tia.OwnerDisplayName,
    tia.OwnerReputation,
    tia.CreationDate,
    tia.LastActivityDate,
    tia.TotalEdits,
    tia.AssociatedTagsString,
    tia.LinkedFromCount,
    tia.DuplicateFromCount,
    tia.LinkedToCount,
    tia.DuplicateToCount,
    tia.RawEngagementScore,
    tia.ActivityDecayFactor,
    tia.QuestionState,
    tia.TitleLength,
    tia.TransformedTitleSegment,
    tia.OverallInfluenceScore,
    tia.OverallRank,
    tia.InfluenceQuintile,
    tia.RankWithinState,
    tia.PreviousQuestionTitleByOwner,
    'Top Impactful Answer' AS InfluenceCategory,
    COALESCE(tia.RawEngagementScore / NULLIF(tia.TotalEdits, 0), 0.0) AS EngagementPerEdit
FROM TopImpactfulAnswers tia
WHERE tia.OverallInfluenceScore > 100
ORDER BY OverallInfluenceScore DESC, CreationDate ASC
LIMIT 1000;
