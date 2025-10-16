WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.LastAccessDate
    FROM
        Users u
    WHERE
        u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
QuestionsWithComments AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        c.CommentCount,
        c.LastCommentDate AS LastActivityDate
    FROM
        Posts p
        LEFT JOIN (
            SELECT
                PostId,
                COUNT(*) AS CommentCount,
                MAX(CreationDate) AS LastCommentDate
            FROM
                Comments
            GROUP BY
                PostId
        ) c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= DATE '2022-01-01'
),
TagStatistics AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT q.QuestionId) AS QuestionCount,
        ROUND(AVG(COALESCE(q.CommentCount, 0)), 2) AS AvgCommentsPerQuestion
    FROM
        Tags t
        JOIN QuestionsWithComments q ON q.Tags LIKE '%' || t.TagName || '%'
    GROUP BY
        t.TagName
),
QuestionAnswers AS (
    SELECT
        p1.Id AS QuestionId,
        COUNT(p2.Id) AS AnswerCount,
        AVG(p2.Score) AS AvgAnswerScore
    FROM
        Posts p1
        LEFT JOIN Posts p2 ON p2.ParentId = p1.Id AND p2.PostTypeId = 2
    GROUP BY
        p1.Id
),
AnswerVoteDistribution AS (
    SELECT
        p.Id AS AnswerId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVotes
    FROM
        Posts p
        LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId = 2
    GROUP BY
        p.Id
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
),
ActivitySummary AS (
    SELECT
        u.Id AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= DATE '2022-01-01' THEN 1 ELSE 0 END) AS QuestionsPosted20,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.LastActivityDate >= DATE '2022-01-01' THEN 1 ELSE 0 END) AS AnswersUpdated20
    FROM
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id
),
MainQuery AS (
    SELECT
        u.UserId,
        u.DisplayName,
        u.Reputation,
        ua.QuestionsPosted20,
        ua.AnswersUpdated20,
        ts.QuestionCount,
        ts.AvgCommentsPerQuestion,
        -- Aggregated per-user question/answer metrics
        pu.QuestionCountUser AS AnswerCount,
        qa_sub.AvgAnswerScore,
        adb.GoldBadges,
        adb.SilverBadges,
        adb.BronzeBadges,
        COALESCE(av_sum.UpVotes, 0) AS UpVotes,
        COALESCE(av_sum.DownVotes, 0) AS DownVotes,
        COALESCE(av_sum.NetVotes, 0) AS NetVotes
    FROM
        ActiveUsers u
        LEFT JOIN ActivitySummary ua ON u.UserId = ua.UserId
        LEFT JOIN TagStatistics ts ON 1=1
        LEFT JOIN (
            SELECT
                p.OwnerUserId AS UserId,
                COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCountUser,
                COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCountUser
            FROM Posts p
            GROUP BY p.OwnerUserId
        ) pu ON pu.UserId = u.UserId
        LEFT JOIN (
            SELECT
                qa.QuestionId,
                qa.AnswerCount,
                qa.AvgAnswerScore
            FROM
                QuestionAnswers qa
        ) qa_sub ON qa_sub.QuestionId IN (
            SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.UserId AND p.PostTypeId = 1
        )
        LEFT JOIN UserBadgeCounts adb ON u.UserId = adb.UserId
        LEFT JOIN (
            SELECT
                avd.AnswerId,
                SUM(avd.UpVotes) AS UpVotes,
                SUM(avd.DownVotes) AS DownVotes,
                SUM(avd.NetVotes) AS NetVotes
            FROM AnswerVoteDistribution avd
            GROUP BY avd.AnswerId
        ) av_sum ON av_sum.AnswerId IN (
            SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.UserId AND p.PostTypeId = 2
        )
)
SELECT
    mq.UserId,
    mq.DisplayName,
    mq.Reputation,
    mq.QuestionsPosted20,
    mq.AnswersUpdated20,
    mq.QuestionCount,
    mq.AvgCommentsPerQuestion,
    mq.AnswerCount,
    mq.AvgAnswerScore,
    mq.GoldBadges,
    mq.SilverBadges,
    mq.BronzeBadges,
    mq.UpVotes,
    mq.DownVotes,
    mq.NetVotes
FROM
    MainQuery mq
WHERE
    mq.Reputation > 1000
    AND (COALESCE(mq.QuestionsPosted20, 0) > 5 OR COALESCE(mq.AnswersUpdated20, 0) > 3)
    AND mq.QuestionCount IS NOT NULL
ORDER BY
    mq.Reputation DESC,
    mq.UserId
LIMIT 50;