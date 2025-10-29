-- {"query": "1337.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3315}
WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COALESCE(u.Location, 'Unspecified') AS UserLocation,
        COUNT(DISTINCT b.Id) AS DistinctBadgesCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        MAX(CASE WHEN b.TagBased = TRUE AND b.Name = 'sql' THEN 1 ELSE 0 END) AS HasSqlTagBadge,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod') THEN 1 ELSE 0 END) AS ReceivedUpVotes,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod') THEN 1 ELSE 0 END) AS ReceivedDownVotes,
        AVG(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'BountyStart') THEN v.BountyAmount ELSE NULL END) AS AvgBountyStarted,
        RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS GlobalReputationRank,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS AnnualReputationRank,
        CASE
            WHEN u.Reputation >= 10000 AND u.Views >= 5000 THEN 'Legendary Contributor'
            WHEN u.Reputation >= 5000 AND u.Views >= 1000 THEN 'Senior Member'
            WHEN u.Reputation >= 1000 THEN 'Active Member'
            ELSE 'Junior Member'
        END AS UserContributionTier
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId
    WHERE u.CreationDate BETWEEN DATE '2010-01-01' AND DATE '2020-12-31'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes, u.Location
    HAVING COUNT(DISTINCT b.Id) > 0 OR u.Reputation > 500
),
PostHistoricalEvolution AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        (SELECT ph_init.Text FROM PostHistory ph_init WHERE ph_init.PostId = p.Id AND ph_init.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Initial Body') ORDER BY ph_init.CreationDate LIMIT 1) AS InitialPostBody,
        (SELECT COUNT(DISTINCT ph_edit.UserId) FROM PostHistory ph_edit WHERE ph_edit.PostId = p.Id AND ph_edit.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE 'Edit %')) AS DistinctEditorsCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL
            THEN (EXTRACT(EPOCH FROM (p.ClosedDate - p.CreationDate)) / 86400.0)
            ELSE NULL
        END AS DaysToClose,
        (SELECT ph_close.Comment FROM PostHistory ph_close WHERE ph_close.PostId = p.Id AND ph_close.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed') ORDER BY ph_close.CreationDate DESC LIMIT 1) AS LastCloseReasonComment,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScoreByOwner,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS OwnerAvgScoreLast4Posts,
        COALESCE(SUM(CASE WHEN pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Linked') THEN 1 ELSE 0 END), 0) AS LinkedToCount,
        COALESCE(SUM(CASE WHEN pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate') THEN 1 ELSE 0 END), 0) AS DuplicateOfCount,
        (CASE
            WHEN p.Tags IS NOT NULL THEN
                array_length(string_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags) - 2)), '><'), 1)
            ELSE 0
         END) AS NumberOfTagsApplied,
        pht.Name AS LastHistoryTypeName,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600 AS HoursSinceCreationToLastActivity,
        EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.Score >= 5 AND c.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')) AS HasRecentHighScoreComment
    FROM Posts AS p
    LEFT JOIN PostLinks AS pl ON p.Id = pl.PostId
    LEFT JOIN (
        SELECT ph.Id, ph.PostId, ph.PostHistoryTypeId, ph.CreationDate
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId NOT IN (1,2,3)
        AND ph.Id IN (
            SELECT ph2.Id FROM (
                SELECT ph_inner.Id,
                       ROW_NUMBER() OVER (PARTITION BY ph_inner.PostId ORDER BY ph_inner.CreationDate DESC) AS rn
                FROM PostHistory ph_inner
                WHERE ph_inner.PostHistoryTypeId NOT IN (1,2,3)
            ) ph2 WHERE ph2.rn = 1
        )
    ) AS ph_latest_event ON p.Id = ph_latest_event.PostId
    LEFT JOIN PostHistoryTypes AS pht ON ph_latest_event.PostHistoryTypeId = pht.Id
    WHERE p.CreationDate BETWEEN DATE '2010-01-01' AND DATE '2020-12-31'
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.LastActivityDate,
        p.Title, p.Tags, pht.Name, ph_latest_event.PostHistoryTypeId, ph_latest_event.CreationDate
),
TagDominance AS (
    SELECT
        t.TagName,
        t.Id AS TagId,
        COUNT(DISTINCT p.Id) AS PostsWithThisTag,
        AVG(p.Score) AS AverageScoreForTag,
        MAX(p.ViewCount) AS MaxViewCountForTag,
        SUM(p.AnswerCount) AS TotalAnswersForTag,
        COALESCE(t.ExcerptPostId, -1) AS ExcerptPostIdStatus,
        COALESCE(t.WikiPostId, -1) AS WikiPostIdStatus,
        (SELECT COUNT(DISTINCT b.UserId) FROM Badges b WHERE b.Name = t.TagName AND b.TagBased = TRUE) AS DistinctTagBadgeOwners
    FROM Tags AS t
    JOIN Posts AS p ON p.Tags LIKE '%' || t.TagName || '%' AND p.Tags IS NOT NULL
    WHERE p.CreationDate BETWEEN DATE '2010-01-01' AND DATE '2020-12-31'
    GROUP BY t.TagName, t.Id, t.ExcerptPostId, t.WikiPostId
    HAVING COUNT(DISTINCT p.Id) > 500
),
CommentSentimentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%thank you%' OR LOWER(c.Text) LIKE '%awesome%' OR LOWER(c.Text) LIKE '%perfect%' THEN 1 ELSE 0 END) AS PositiveCommentCount,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%bug%' OR LOWER(c.Text) LIKE '%error%' OR LOWER(c.Text) LIKE '%wrong%' THEN 1 ELSE 0 END) AS NegativeCommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    WHERE c.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 year')
    GROUP BY c.PostId
    HAVING COUNT(c.Id) > 5
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.UserContributionTier,
    ues.DistinctBadgesCount,
    ues.HasSqlTagBadge,
    phe.PostId,
    pt.Name AS PostTypeName,
    phe.PostCreationDate,
    phe.Score AS PostScore,
    phe.ViewCount,
    phe.CommentCount AS PostRawCommentCount,
    phe.FavoriteCount,
    phe.DaysToClose,
    phe.DistinctEditorsCount,
    phe.LastCloseReasonComment,
    phe.NumberOfTagsApplied,
    phe.LinkedToCount,
    phe.DuplicateOfCount,
    phe.PreviousPostScoreByOwner,
    phe.OwnerAvgScoreLast4Posts,
    td.TagName AS PrimaryDominantTag,
    td.AverageScoreForTag,
    td.PostsWithThisTag AS DominantTagPostCount,
    COALESCE(csa.TotalComments, 0) AS RecentCommentTotal,
    COALESCE(csa.AvgCommentScore, 0.0) AS RecentAvgCommentScore,
    COALESCE(csa.PositiveCommentCount, 0) AS RecentPositiveCommentCount,
    COALESCE(csa.NegativeCommentCount, 0) AS RecentNegativeCommentCount,
    (phe.Score * 0.35) +
    (phe.ViewCount / 1000.0 * 0.20) +
    (COALESCE(csa.TotalComments, 0) * 0.15) +
    (phe.FavoriteCount * 0.20) +
    (CASE WHEN phe.DaysToClose IS NULL THEN 10 ELSE -5 END) +
    (phe.DistinctEditorsCount * 2) +
    (COALESCE(td.AverageScoreForTag, 0) / 10.0 * 0.05) +
    (CASE WHEN phe.HasRecentHighScoreComment THEN 3 ELSE 0 END) AS CalculatedEngagementScore,
    (SELECT COUNT(DISTINCT p_owner_specific.Id)
     FROM Posts AS p_owner_specific
     WHERE p_owner_specific.OwnerUserId = ues.UserId
       AND p_owner_specific.PostTypeId IN (SELECT Id FROM PostTypes WHERE Name IN ('Wiki', 'TagWiki'))
       AND p_owner_specific.CreationDate > ues.UserCreationDate
    ) AS OwnerWikiContributionsAfterJoin,
    UPPER(SUBSTRING(COALESCE(phe.Title, 'No Title') FROM 1 FOR 20)) AS TitlePrefixUpper,
    NULLIF(TRIM(SUBSTRING(phe.Tags FROM 2 FOR (CHAR_LENGTH(phe.Tags) - 2))), '') AS FirstTag,
    (phe.InitialPostBody LIKE '%example%') AS ContainsExampleKeywordInBody,
    (pt.Name IN ('Question', 'Answer')) AS IsStandardPostType,
    (EXISTS (SELECT 1 FROM PostHistory ph_mig WHERE ph_mig.PostId = phe.PostId AND ph_mig.PostHistoryTypeId IN (SELECT Id FROM PostHistoryTypes WHERE Name LIKE 'Post Migrated %'))) AS WasMigrated,
    ues.GlobalReputationRank,
    phe.LastActivityDate
FROM UserEngagementSummary AS ues
INNER JOIN PostHistoricalEvolution AS phe
    ON ues.UserId = phe.OwnerUserId
INNER JOIN PostTypes AS pt
    ON phe.PostTypeId = pt.Id
LEFT JOIN TagDominance AS td
    ON phe.Tags LIKE '%' || td.TagName || '%' AND (POSITION(td.TagName IN phe.Tags) = 2)
LEFT JOIN CommentSentimentAnalysis AS csa
    ON phe.PostId = csa.PostId
WHERE
    ues.Reputation > 1000
    AND phe.ViewCount > 1000
    AND phe.Score > 50
    AND phe.PostTypeId IN (SELECT Id FROM PostTypes WHERE Name IN ('Question', 'Answer'))
    AND (phe.LastActivityDate BETWEEN (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 year') AND TIMESTAMP '2024-10-01 12:34:56')
    AND (phe.Tags IS NOT NULL AND phe.Tags <> '')
    AND (
        (phe.DistinctEditorsCount > 1 AND phe.LastCloseReasonComment IS NULL) OR
        (phe.FavoriteCount > 50 AND phe.NumberOfTagsApplied <= 3) OR
        (COALESCE(csa.PositiveCommentCount,0) > COALESCE(csa.NegativeCommentCount,0) AND COALESCE(csa.TotalComments,0) > 10)
    )
ORDER BY
    CalculatedEngagementScore DESC,
    ues.GlobalReputationRank ASC,
    phe.LastActivityDate DESC
LIMIT 5000;