WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        (SELECT MAX(ph.CreationDate)
         FROM PostHistory ph
         WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 2) AS LastBodyEditDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 1000 AND u.CreationDate < (DATE '2024-10-01' - INTERVAL '5' YEAR)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 10
),
RankedQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        q.CreationDate AS QuestionCreationDate,
        q.FavoriteCount,
        q.AcceptedAnswerId,
        COALESCE(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), 'untagged') AS PrimaryTag,
        ROW_NUMBER() OVER(PARTITION BY q.OwnerUserId ORDER BY q.ViewCount DESC, q.Score DESC) as rn
    FROM
        Posts q
    WHERE
        q.PostTypeId = 1
        AND q.OwnerUserId IN (SELECT UserId FROM UserActivity WHERE GoldBadges > 0)
        AND q.ClosedDate IS NULL
),
AggregatedPostHistory AS (
    SELECT
        ph.PostId,
        COUNT(*) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        string_agg(DISTINCT crt.Name, ', ') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^[0-9]+$') AS CloseReasons
    FROM
        PostHistory ph
    LEFT JOIN
        CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE PostId IN (SELECT QuestionId FROM RankedQuestions WHERE rn <= 5)
    GROUP BY
        ph.PostId
),
CombinedData AS (
    SELECT
        rq.OwnerUserId,
        rq.QuestionId,
        rq.Title,
        rq.PrimaryTag,
        rq.QuestionScore,
        rq.ViewCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags LIKE ('%' || rq.PrimaryTag || '%')) AS AvgScoreForTag,
        ans.Id AS AnswerId,
        ans.Score AS AnswerScore,
        ans_user.DisplayName AS AnswererDisplayName,
        ans_user.Reputation AS AnswererReputation,
        EXTRACT(EPOCH FROM (ans.CreationDate - rq.QuestionCreationDate))/3600 AS HoursToAnswer,
        aph.EditCount,
        aph.CloseVoteCount,
        aph.CloseReasons,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.QuestionId) AS QuestionCommentCount
    FROM
        RankedQuestions rq
    LEFT JOIN
        Posts ans ON rq.AcceptedAnswerId = ans.Id
    LEFT JOIN
        Users ans_user ON ans.OwnerUserId = ans_user.Id
    LEFT JOIN
        AggregatedPostHistory aph ON rq.QuestionId = aph.PostId
    WHERE
        rq.rn <= 5
)
SELECT
    ua.DisplayName AS Questioner,
    ua.Reputation AS QuestionerReputation,
    cd.Title AS QuestionTitle,
    cd.PrimaryTag,
    cd.QuestionScore,
    cd.ViewCount,
    cd.QuestionScore - cd.AvgScoreForTag AS ScoreVsTagAverage,
    CASE
        WHEN cd.AnswererDisplayName IS NULL THEN 'NO_ACCEPTED_ANSWER'
        ELSE cd.AnswererDisplayName || ' (Rep: ' || COALESCE(cd.AnswererReputation, 0) || ')'
    END AS AnswererInfo,
    cd.HoursToAnswer,
    COALESCE(cd.EditCount, 0) AS Edits,
    COALESCE(cd.CloseVoteCount, 0) AS CloseVotes,
    cd.QuestionCommentCount,
    (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = cd.QuestionId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = cd.QuestionId AND v.VoteTypeId = 3) AS Downvotes
FROM
    CombinedData cd
JOIN
    UserActivity ua ON cd.OwnerUserId = ua.UserId
WHERE
    cd.QuestionScore > 0
    AND (cd.AnswererReputation > ua.Reputation OR cd.AnswererReputation IS NULL)
ORDER BY
    ua.Reputation DESC,
    cd.ViewCount DESC,
    cd.QuestionScore DESC
LIMIT 200;