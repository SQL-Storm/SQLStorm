-- {"query": "1333.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2981}
WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        (
            COALESCE(u.Reputation, 0) * 0.15 +
            COALESCE(u.UpVotes, 0) * 0.5 -
            COALESCE(u.DownVotes, 0) * 0.2 +
            COALESCE(u.Views, 0) * 0.01 +
            (SELECT COUNT(b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Date >= u.CreationDate) * 1.0
        ) AS TotalEngagementScore,
        COUNT(p.Id) AS PostsCreated,
        COUNT(c.Id) AS CommentsMade,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS RepRankInCreationYear
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE
        u.CreationDate >= DATE '2015-01-01'
        AND u.Reputation > 500
        AND u.LastAccessDate >= (DATE '2024-10-01' - INTERVAL '1 year')
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate, u.LastAccessDate
    HAVING
        COUNT(p.Id) >= 5 AND COUNT(c.Id) >= 10
),
PostVersionComplexity AS (
    SELECT
        ph.PostId,
        ph.UserId AS HistoryUserId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.Comment,
        CASE WHEN ph.UserId = (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = ph.PostId) THEN 1 ELSE 0 END AS IsOwnerEdit,
        NULL AS UniqueHistoryTypeCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeEditCount,
        EXTRACT(DAY FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) AS DaysSincePrevHistory
    FROM PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4,5,6,10,11,12,13)
        AND ph.CreationDate >= DATE '2018-01-01'
),
PostVersionUniqueTypes AS (
    SELECT ph.PostId, COUNT(DISTINCT ph.PostHistoryTypeId) AS UniqueHistoryTypeCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,11,12,13)
      AND ph.CreationDate >= DATE '2018-01-01'
    GROUP BY ph.PostId
),
PostVersionComplexityFinal AS (
    SELECT pvc.PostId,
           pvc.HistoryUserId,
           pvc.PostHistoryTypeId,
           pvc.HistoryDate,
           pvc.Comment,
           pvc.IsOwnerEdit,
           COALESCE(pvut.UniqueHistoryTypeCount, 0) AS UniqueHistoryTypeCount,
           pvc.CumulativeEditCount,
           pvc.DaysSincePrevHistory
    FROM PostVersionComplexity pvc
    LEFT JOIN PostVersionUniqueTypes pvut ON pvc.PostId = pvut.PostId
),
DetailedPostAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.Body,
        p.LastActivityDate,
        p.ClosedDate,
        pvc.UniqueHistoryTypeCount,
        pvc.CumulativeEditCount,
        pvc.DaysSincePrevHistory,
        (
            SELECT crt.Name
            FROM PostHistory ph_close
            JOIN CloseReasonTypes crt ON crt.Id = CAST(ph_close.Comment AS SMALLINT)
            WHERE ph_close.PostId = p.Id AND ph_close.PostHistoryTypeId = 10
            ORDER BY ph_close.CreationDate DESC
            LIMIT 1
        ) AS LastCloseReason,
        COALESCE(
            CASE
                WHEN p.Tags IS NOT NULL AND POSITION('><' IN p.Tags) > 0 THEN SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags) - 2)
                WHEN p.Tags IS NOT NULL THEN TRIM(BOTH '<>' FROM p.Tags)
                ELSE NULL
            END,
            'Untagged'
        ) AS PrimaryTag,
        (
            pvc.CumulativeEditCount * 2.0 +
            COALESCE(p.CommentCount, 0) * 0.8 +
            CASE
                WHEN p.ViewCount IS NOT NULL AND p.ViewCount > 1000 THEN 5.0
                WHEN p.ViewCount IS NOT NULL AND p.ViewCount > 500 THEN 2.0
                ELSE 0.0
            END -
            COALESCE(p.Score, 0) * 0.1
        ) AS ControversyScore,
        (LOWER(p.Body) LIKE '%error%' OR LOWER(p.Body) LIKE '%bug%' OR LOWER(p.Body) LIKE '%issue%') AS ContainsProblemKeywords
    FROM Posts p
    LEFT JOIN PostVersionComplexityFinal pvc ON p.Id = pvc.PostId
    WHERE
        p.PostTypeId IN (1,2)
        AND p.OwnerUserId IS NOT NULL
        AND p.CreationDate >= DATE '2018-01-01'
        AND COALESCE(pvc.UniqueHistoryTypeCount, 0) >= 2
        AND COALESCE(pvc.CumulativeEditCount, 0) >= 2
),
FinalUserPostAnalysis AS (
    SELECT
        ues.UserId,
        ues.UserName,
        ues.TotalEngagementScore,
        ues.RepRankInCreationYear,
        dpa.PostId,
        dpa.PostTypeId,
        dpa.PostCreationDate,
        dpa.Title,
        dpa.PrimaryTag,
        dpa.ControversyScore,
        dpa.LastCloseReason,
        dpa.ContainsProblemKeywords,
        dpa.Score,
        dpa.ViewCount,
        dpa.CommentCount,
        AVG(dpa.ControversyScore) OVER (PARTITION BY ues.UserId) AS AvgUserControversyScore,
        ROW_NUMBER() OVER (PARTITION BY ues.UserId ORDER BY dpa.ControversyScore DESC, dpa.PostCreationDate DESC) AS UserControversyRank,
        COALESCE(
            UPPER(SUBSTRING(dpa.Title FROM 1 FOR 1)) || LOWER(SUBSTRING(dpa.Title FROM 2)) || ' [' || dpa.PrimaryTag || ']',
            'UNKNOWN POST [' || dpa.PrimaryTag || ']'
        ) AS FormattedPostTitleTag
    FROM UserEngagementSummary ues
    JOIN DetailedPostAnalysis dpa ON ues.UserId = dpa.OwnerUserId
    WHERE
        dpa.Score >= 0
        AND dpa.ControversyScore > 10
        AND dpa.Title IS NOT NULL
        AND dpa.PrimaryTag != 'Untagged'
)
SELECT
    fupa.UserId,
    fupa.UserName,
    fupa.TotalEngagementScore,
    fupa.FormattedPostTitleTag,
    fupa.ControversyScore,
    fupa.AvgUserControversyScore,
    fupa.UserControversyRank,
    fupa.LastCloseReason,
    fupa.ContainsProblemKeywords,
    COALESCE(lt.Name, 'No Related Link') AS RelatedLinkType,
    COALESCE(p_accepted.Title, 'No Accepted Answer') AS AcceptedAnswerTitle,
    CASE
        WHEN fupa.ViewCount > 0 THEN CAST(fupa.Score AS NUMERIC) / fupa.ViewCount
        ELSE 0.0
    END AS ScoreToViewRatio,
    EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = fupa.PostId
          AND v.VoteTypeId = 8
          AND v.UserId = fupa.UserId
          AND v.BountyAmount > 0
    ) AS HasActiveBounty,
    LEFT(MD5(CAST(fupa.PostId AS VARCHAR) || fupa.FormattedPostTitleTag), 8) AS PostHashId
FROM FinalUserPostAnalysis fupa
LEFT JOIN PostLinks pl ON fupa.PostId = pl.PostId AND pl.LinkTypeId = 1
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN Posts p_accepted ON fupa.PostTypeId = 1 AND fupa.PostId = p_accepted.AcceptedAnswerId
WHERE
    fupa.RepRankInCreationYear <= 50
    AND fupa.UserControversyRank <= 5
    AND fupa.TotalEngagementScore > 1000
    AND (
        fupa.LastCloseReason IS NOT NULL
        OR fupa.ContainsProblemKeywords
    )
    AND NOT EXISTS (
        SELECT 1
        FROM PostVersionComplexityFinal pvc_inner
        WHERE pvc_inner.PostId = fupa.PostId
          AND pvc_inner.PostHistoryTypeId = 12
          AND EXISTS (
              SELECT 1
              FROM PostVersionComplexityFinal pvc_undelete
              WHERE pvc_undelete.PostId = pvc_inner.PostId
                AND pvc_undelete.PostHistoryTypeId = 13
                AND pvc_undelete.HistoryDate BETWEEN pvc_inner.HistoryDate AND pvc_inner.HistoryDate + INTERVAL '1 hour'
          )
    )
    AND fupa.PostId IN (
        SELECT p_set.Id
        FROM Posts p_set
        WHERE p_set.PostTypeId = 1
          AND p_set.AnswerCount >= 3
          AND p_set.CommentCount >= 2
          AND p_set.CreationDate BETWEEN fupa.PostCreationDate - INTERVAL '90 days' AND fupa.PostCreationDate + INTERVAL '90 days'
    )
ORDER BY
    fupa.TotalEngagementScore DESC,
    fupa.ControversyScore DESC,
    ScoreToViewRatio DESC
LIMIT 200;