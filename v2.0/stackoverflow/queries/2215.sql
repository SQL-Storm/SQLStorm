-- {"query": "2215.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1702}
WITH RecursiveTagStats AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count,
        p.OwnerUserId,
        u.DisplayName,
        row_number() OVER (PARTITION BY t.Id ORDER BY p.Score DESC NULLS LAST, p.CreationDate) AS rn,
        count(*) OVER (PARTITION BY t.Id) AS TagPostCount,
        sum(coalesce(p.Score,0)) OVER (PARTITION BY t.Id) AS TagScoreSum
    FROM 
        Tags t
        LEFT JOIN Posts p ON p.PostTypeId = 1 AND position('<' || t.TagName || '>' IN coalesce(p.Tags, '')) > 0
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE 
        t.IsModeratorOnly = false AND t.IsRequired = false
), TopPostersPerTag AS (
    SELECT 
        TagId, TagName, OwnerUserId, DisplayName, rn
    FROM RecursiveTagStats
    WHERE rn <= 3
), PostBadgesAgg AS (
    SELECT 
        b.UserId,
        string_agg(b.Name || ' (' || b.Class || ')', ', ' ORDER BY b.Class, b.Name) AS Badges,
        count(case when b.Class = 1 then 1 end) AS GoldBadges,
        count(case when b.Class = 2 then 1 end) AS SilverBadges,
        count(case when b.Class = 3 then 1 end) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
), PostAnswerWindow AS (
    SELECT 
        p.Id, p.ParentId, p.Score, p.CreationDate, p.OwnerUserId,
        row_number() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC NULLS LAST, p.CreationDate) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2
), CteQuestionsWithAcceptedAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId AS QuestionOwner,
        q.CreationDate AS QuestionDate,
        aa.Id AS AcceptedAnswerId,
        aa.Score AS AcceptedAnswerScore,
        aa.OwnerUserId AS AcceptedAnswerOwner,
        coalesce(ba.Badges,'') AS AcceptedAnswerBadges
    FROM 
        Posts q
        LEFT JOIN Posts aa ON aa.Id = q.AcceptedAnswerId
        LEFT JOIN PostBadgesAgg ba ON ba.UserId = aa.OwnerUserId
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
), CloseVoteCounts AS (
    SELECT 
        ph.PostId,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) AS CloseVotesCount,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) AS LastCloseVoteDate,
        -- CloseReasonComment cannot be an aggregate with window here; use max() of the expression
        max(case when ph.PostHistoryTypeId = 10 then nullif(ph.Comment, '') end) AS CloseReasonComment
    FROM 
        PostHistory ph
    GROUP BY ph.PostId
), ComplexFilteredQuestions AS (
    SELECT 
        q.Id, q.Title, q.Score, q.ViewCount, q.Tags, q.CreationDate, q.OwnerUserId,
        coalesce(cvc.CloseVotesCount,0) AS CloseVotesCount,
        cvc.LastCloseVoteDate,
        cr.Name AS CloseReasonName
    FROM 
        Posts q
        LEFT JOIN CloseVoteCounts cvc ON cvc.PostId = q.Id
        LEFT JOIN CloseReasonTypes cr ON cr.Id = (
            SELECT max(CAST(ph.Comment AS integer)) FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^\d+$'
        )
    WHERE 
        q.PostTypeId = 1
        AND (q.Score > 5 OR q.ViewCount > 1000 OR coalesce(cvc.CloseVotesCount,0) > 0)
), UnionedPostJoin AS (
    SELECT 
        q.Id AS QuestionId,
        a.Id AS AnswerId,
        u.DisplayName AS QuestionOwnerName,
        ua.DisplayName AS AnswerOwnerName,
        q.Score AS QuestionScore,
        a.Score AS AnswerScore,
        q.Tags,
        pb.Badges AS AnswerOwnerBadges,
        row_number() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST) AS AnswerOrd
    FROM 
        Posts q
        LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
        LEFT JOIN Users u ON u.Id = q.OwnerUserId
        LEFT JOIN Users ua ON ua.Id = a.OwnerUserId
        LEFT JOIN PostBadgesAgg pb ON pb.UserId = a.OwnerUserId
    WHERE q.PostTypeId = 1
), CorrelatedSubQueryTopComment AS (
    SELECT 
        p.Id AS PostId,
        (SELECT c.Text FROM Comments c WHERE c.PostId = p.Id ORDER BY c.Score DESC NULLS LAST LIMIT 1) AS TopCommentText,
        (SELECT c.UserDisplayName FROM Comments c WHERE c.PostId = p.Id ORDER BY c.Score DESC NULLS LAST LIMIT 1) AS TopCommentUser,
        (SELECT c.Score FROM Comments c WHERE c.PostId = p.Id ORDER BY c.Score DESC NULLS LAST LIMIT 1) AS TopCommentScore
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
), WindowFunctionRanks AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        dense_rank() OVER (ORDER BY p.Score DESC NULLS LAST) AS ScoreRank,
        ntile(5) OVER (ORDER BY p.ViewCount DESC NULLS LAST) AS ViewCountTile,
        lag(p.Score) OVER (ORDER BY p.Score DESC NULLS LAST) AS PrevScore,
        lead(p.Score) OVER (ORDER BY p.Score DESC NULLS LAST) AS NextScore
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT
    q.Id AS QuestionId,
    q.Title,
    q.Score,
    q.ViewCount,
    q.Tags,
    q.CreationDate,
    u.DisplayName AS QuestionOwner,
    pb.Badges AS QuestionOwnerBadges,
    cvc.CloseVotesCount,
    cvc.LastCloseVoteDate,
    cr.Name AS CloseReasonName,
    coalesce(cca.AcceptedAnswerScore,0) AS AcceptedAnswerScore,
    cca.AcceptedAnswerBadges,
    ts.TopPosters,
    tc.TopCommentText,
    tc.TopCommentUser,
    tc.TopCommentScore,
    wfr.ScoreRank,
    wfr.ViewCountTile,
    wfr.PrevScore,
    wfr.NextScore
FROM 
    ComplexFilteredQuestions q
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN PostBadgesAgg pb ON pb.UserId = q.OwnerUserId
    LEFT JOIN CloseVoteCounts cvc ON cvc.PostId = q.Id
    LEFT JOIN CloseReasonTypes cr ON cr.Id = (
        SELECT max(CAST(ph.Comment AS integer)) FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^\d+$'
    )
    LEFT JOIN CteQuestionsWithAcceptedAnswers cca ON cca.QuestionId = q.Id
    LEFT JOIN (
        SELECT 
            TagId,
            TagName,
            string_agg(DisplayName, ', ' ORDER BY rn) AS TopPosters
        FROM TopPostersPerTag
        GROUP BY TagId, TagName
    ) ts ON position('<' || ts.TagName || '>' IN coalesce(q.Tags, '')) > 0
    LEFT JOIN CorrelatedSubQueryTopComment tc ON tc.PostId = q.Id
    LEFT JOIN WindowFunctionRanks wfr ON wfr.Id = q.Id
WHERE 
    (q.ViewCount > 500 OR q.Score > 10 OR cvc.CloseVotesCount > 0)
ORDER BY q.ViewCount DESC NULLS LAST, q.Score DESC NULLS LAST
LIMIT 100;