-- {"query": "50031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1339} 

WITH UserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.UpVotes,
        u.DownVotes,
        EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / 86400 AS MemberDays,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM
        Users u
    WHERE
        u.Reputation > 1500 AND u.Id > 0
),
PostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
        SUM(p.FavoriteCount) FILTER (WHERE p.PostTypeId = 1) AS TotalFavoriteCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        COUNT(q.AcceptedAnswerId) AS AcceptedAnswers
    FROM
        Posts p
    LEFT JOIN
        Posts q ON p.Id = q.AcceptedAnswerId
    WHERE
        p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId
),
EngagementStats AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.UserId = c.UserId AND v.VoteTypeId = 2) AS UpVotesGiven
    FROM
        Comments c
    WHERE
        c.UserId IS NOT NULL
    GROUP BY
        c.UserId
),
RankedScores AS (
    SELECT
        um.UserId,
        um.DisplayName,
        um.Reputation,
        um.CreationDate,
        um.GoldBadges,
        um.SilverBadges,
        um.BronzeBadges,
        COALESCE(ps.QuestionCount, 0) AS QuestionCount,
        COALESCE(ps.AnswerCount, 0) AS AnswerCount,
        COALESCE(ps.AcceptedAnswers, 0) AS AcceptedAnswers,
        COALESCE(ps.TotalScore, 0) AS TotalPostScore,
        COALESCE(es.CommentCount, 0) AS CommentCount,
        COALESCE(es.UpVotesGiven, 0) AS UpVotesGiven,
        (
            -- Score Calculation
            (um.Reputation * 0.1) +
            (COALESCE(ps.TotalScore, 0) * 0.2) +
            (COALESCE(ps.AcceptedAnswers, 0) * 20) +
            (um.GoldBadges * 100) +
            (um.SilverBadges * 50) +
            (um.BronzeBadges * 25) +
            (COALESCE(es.CommentCount, 0) * 0.05) +
            (COALESCE(es.UpVotesGiven, 0) * 0.02) +
            (COALESCE(ps.TotalQuestionViews, 0) * 0.001) +
            (um.MemberDays * 0.1)
        ) AS CompositeScore,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM um.CreationDate) ORDER BY um.Reputation DESC) AS RankInYear
    FROM
        UserMetrics um
    JOIN
        PostStats ps ON um.UserId = ps.OwnerUserId
    LEFT JOIN
        EngagementStats es ON um.UserId = es.UserId
    WHERE
        ps.AnswerCount > ps.QuestionCount AND ps.AnswerCount > 10
)
SELECT
    rs.DisplayName,
    rs.Reputation,
    rs.CreationDate,
    rs.CompositeScore,
    rs.QuestionCount,
    rs.AnswerCount,
    rs.AcceptedAnswers,
    rs.GoldBadges,
    rs.RankInYear,
    (
        SELECT
            p_sub.Title
        FROM
            Posts p_sub
        WHERE
            p_sub.OwnerUserId = rs.UserId AND p_sub.PostTypeId = 1
        ORDER BY
            p_sub.Score DESC, p_sub.FavoriteCount DESC
        LIMIT 1
    ) AS TopQuestionTitle,
    (
        SELECT string_agg(t.TagName, ', ')
        FROM Tags t
        JOIN (
            SELECT
                unnest(string_to_array(substring(p_tags.Tags, 2, length(p_tags.Tags)-2), '><')) AS TagName,
                p_tags.OwnerUserId
            FROM Posts p_tags
            WHERE p_tags.OwnerUserId = rs.UserId AND p_tags.PostTypeId = 1 AND p_tags.Tags IS NOT NULL
        ) AS user_tags ON t.TagName = user_tags.TagName
        GROUP BY user_tags.OwnerUserId
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS MostUsedTag
FROM
    RankedScores rs
WHERE
    rs.RankInYear <= 10
ORDER BY
    EXTRACT(YEAR FROM rs.CreationDate), rs.RankInYear;
