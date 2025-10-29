-- {"query": "1665.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3216}
WITH UserInfluence AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (u.Reputation * 0.1 + u.Views * 0.01 + COUNT(DISTINCT b.Id) * 5 + SUM(CASE WHEN b.Class = 1 THEN 10 ELSE 0 END)) AS InfluenceScore,
        CASE
            WHEN u.Reputation > 50000 AND SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) >= 10 THEN TRUE
            ELSE FALSE
        END AS IsSuperContributor
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
PostEngagementSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(DISTINCT ph.Id) AS HistoryEntryCount,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MAX(ph.CreationDate) AS LatestEditActivityDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteCount,
        SUM(CASE WHEN v.VoteTypeId IN (2,3,5) THEN 1 ELSE 0 END) AS TotalInteractionVotes,
        (COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) * 2 +
         COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) * 0.5 +
         COALESCE(COUNT(DISTINCT c.Id), 0) * 3 +
         COALESCE(COUNT(DISTINCT ph.Id), 0) * 0.1) AS EngagementScore
    FROM Posts AS p
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6, 8, 9, 10, 11)
    GROUP BY p.Id
),
RecentPostClosureEvents AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenedDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseEventCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenEventCount,
        -- use standard aggregation for concatenation where available; fallback to STRING_AGG if supported
        STRING_AGG(DISTINCT crt.Name, '; ') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL) AS AllCloseReasons
    FROM PostHistory AS ph
    LEFT JOIN CloseReasonTypes AS crt ON ph.PostHistoryTypeId = 10 AND crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE ph.PostHistoryTypeId IN (10, 11)
    GROUP BY ph.PostId
),
QuestionTagsExpanded AS (
    SELECT
        p.Id AS PostId,
        -- normalize tag extraction to standard functions
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), '><')) AS TagName
    FROM Posts AS p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND CHAR_LENGTH(p.Tags) > 2
),
TagPerformance AS (
    SELECT
        qt.TagName,
        AVG(p.Score) AS AvgScore,
        AVG(p.ViewCount) AS AvgViewCount,
        COUNT(p.Id) AS QuestionCount,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM QuestionTagsExpanded AS qt
    JOIN Posts AS p ON qt.PostId = p.Id
    GROUP BY qt.TagName
),
RankedTagPerformance AS (
    SELECT
        tp.TagName,
        tp.AvgScore,
        tp.AvgViewCount,
        tp.QuestionCount,
        tp.AcceptedAnswerCount,
        RANK() OVER (ORDER BY tp.AvgScore DESC, tp.AvgViewCount DESC) AS TagScoreRank
    FROM TagPerformance AS tp
),
QuestionPrimaryTag AS (
    SELECT
        qte.PostId,
        qte.TagName AS PrimaryTagName,
        rtp.AvgScore AS PrimaryTagAvgScore,
        rtp.TagScoreRank AS PrimaryTagPopularityRank,
        ROW_NUMBER() OVER (PARTITION BY qte.PostId ORDER BY rtp.TagScoreRank ASC, qte.TagName ASC) AS rn
    FROM QuestionTagsExpanded AS qte
    JOIN RankedTagPerformance AS rtp ON qte.TagName = rtp.TagName
)
SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate AS QuestionCreationDate,
    q.ViewCount,
    q.Score AS QuestionScore,
    q.AnswerCount,
    q.FavoriteCount,
    ui_owner.DisplayName AS OwnerDisplayName,
    ui_owner.Reputation AS OwnerReputation,
    ui_owner.InfluenceScore AS OwnerInfluenceScore,
    pes.EngagementScore AS PostEngagementScore,
    pes.UpVoteCount AS QuestionUpVotes,
    pes.DownVoteCount AS QuestionDownVotes,
    pes.CommentCount AS TotalComments,
    pes.DistinctEditors AS UniqueEditorsCount,
    rpe.LastClosedDate,
    rpe.LastReopenedDate,
    rpe.AllCloseReasons,
    (q.ClosedDate IS NOT NULL) AS IsClosed,
    COALESCE(q.LastActivityDate, q.CreationDate) AS LastActivityDateTime,
    (SELECT COUNT(DISTINCT a.Id) FROM Posts AS a WHERE a.ParentId = q.Id AND a.PostTypeId = 2 AND a.AcceptedAnswerId = q.Id) AS AcceptedAnswersToThisQuestion,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks AS pl
     WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3) AS DuplicatePostLinksCount,
    (
        SELECT
            CASE
                WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = q.OwnerUserId AND b.Name = 'Disciplined') THEN 'Has Disciplined Badge'
                WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = q.OwnerUserId AND b.Name = 'Strunk & White') THEN 'Has Strunk & White Badge'
                ELSE 'No Specific Editing Badge'
            END
    ) AS OwnerEditingBadgeStatus,
    STRING_AGG(DISTINCT qte_all.TagName, ', ') AS AllQuestionTags,
    qp_tag.PrimaryTagName AS MainTag,
    qp_tag.PrimaryTagAvgScore AS MainTagAvgScore,
    qp_tag.PrimaryTagPopularityRank AS MainTagPopularityRank,
    AVG(q.Score) OVER (PARTITION BY ui_owner.UserId ORDER BY q.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS OwnerRecentAvgScore,
    RANK() OVER (PARTITION BY qp_tag.PrimaryTagName ORDER BY q.Score DESC, q.ViewCount DESC) AS RankWithinMainTag,
    NTILE(10) OVER (ORDER BY q.ViewCount DESC) AS ViewCountDecile,
    (CAST(pes.UpVoteCount AS NUMERIC) / NULLIF(pes.UpVoteCount + pes.DownVoteCount, 0)) AS UpvoteDownvoteRatio,
    CASE
        WHEN q.AcceptedAnswerId IS NOT NULL AND q.ClosedDate IS NULL THEN 'Answered & Open'
        WHEN q.AcceptedAnswerId IS NULL AND q.ClosedDate IS NULL THEN 'Unanswered & Open'
        WHEN q.AcceptedAnswerId IS NOT NULL AND q.ClosedDate IS NOT NULL THEN 'Answered & Closed'
        WHEN q.AcceptedAnswerId IS NULL AND q.ClosedDate IS NOT NULL THEN 'Unanswered & Closed'
        ELSE 'Unknown Status'
    END AS QuestionStatus,
    COALESCE(q.CommunityOwnedDate, TIMESTAMP '1900-01-01 00:00:00') AS CommunityOwnedOrDefaultDate,
    LEFT(TRIM(SUBSTRING(q.Body FROM 1 FOR 200)), 150) || '...' AS BodySnippet
FROM Posts AS q
INNER JOIN PostTypes AS pt ON q.PostTypeId = pt.Id AND pt.Name = 'Question'
LEFT JOIN UserInfluence AS ui_owner ON q.OwnerUserId = ui_owner.UserId
LEFT JOIN PostEngagementSummary AS pes ON q.Id = pes.PostId
LEFT JOIN RecentPostClosureEvents AS rpe ON q.Id = rpe.PostId
LEFT JOIN QuestionPrimaryTag AS qp_tag ON q.Id = qp_tag.PostId AND qp_tag.rn = 1
LEFT JOIN QuestionTagsExpanded AS qte_all ON q.Id = qte_all.PostId
WHERE
    q.CreationDate >= DATE '2022-01-01'
    AND q.ViewCount > 1000
    AND q.Score > 10
    AND (q.ClosedDate IS NULL OR q.LastActivityDate > q.ClosedDate - INTERVAL '30' DAY)
    AND q.Body LIKE '%performance%'
    AND (pes.UpVoteCount IS NULL OR pes.UpVoteCount > 5)
    AND (ui_owner.IsSuperContributor = TRUE OR ui_owner.InfluenceScore > 500)
    AND q.Id IN (
        SELECT DISTINCT PostId
        FROM Comments
        WHERE CreationDate > (DATE '2024-10-01' - INTERVAL '60' DAY) AND CHAR_LENGTH(Text) > 50
    )
GROUP BY
    q.Id, q.Title, q.CreationDate, q.ViewCount, q.Score, q.AnswerCount, q.FavoriteCount,
    ui_owner.DisplayName, ui_owner.Reputation, ui_owner.InfluenceScore, ui_owner.UserId,
    pes.EngagementScore, pes.UpVoteCount, pes.DownVoteCount, pes.CommentCount, pes.DistinctEditors,
    rpe.LastClosedDate, rpe.LastReopenedDate, rpe.AllCloseReasons, q.ClosedDate,
    q.LastActivityDate, q.OwnerUserId, q.CommunityOwnedDate, q.Body,
    qp_tag.PrimaryTagName, qp_tag.PrimaryTagAvgScore, qp_tag.PrimaryTagPopularityRank,
    q.AcceptedAnswerId
HAVING
    COUNT(DISTINCT qte_all.TagName) > 1
    AND (CAST(SUM(COALESCE(pes.UpVoteCount,0)) AS NUMERIC) / NULLIF(CAST(SUM(COALESCE(pes.UpVoteCount,0) + COALESCE(pes.DownVoteCount,0)) AS NUMERIC), 0)) > 0.7
ORDER BY
    OwnerInfluenceScore DESC,
    QuestionScore DESC,
    QuestionCreationDate DESC
LIMIT 1000;