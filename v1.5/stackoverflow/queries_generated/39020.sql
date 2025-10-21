-- {"query": "39020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2482} 

WITH QuestionTags AS (
    SELECT
        p.Id,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        qt.Tag,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)        AS AnswersGiven,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)    AS TotalAnsScore
    FROM Posts p
    JOIN QuestionTags qt
      ON qt.Id = p.ParentId
    GROUP BY p.OwnerUserId, qt.Tag
),
CommentStats AS (
    SELECT
        c.UserId,
        COUNT(*)                   AS CommentsMade,
        AVG(char_length(c.Text))   AS AvgCommentLength
    FROM Comments c
    GROUP BY c.UserId
),
BadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER(WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER(WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER(WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteStats AS (
    SELECT
        v.UserId,
        COUNT(*) FILTER(WHERE v.VoteTypeId = 2)  AS UpVotes,
        COUNT(*) FILTER(WHERE v.VoteTypeId = 3)  AS DownVotes,
        COUNT(*) FILTER(WHERE v.VoteTypeId = 5)  AS Favorites
    FROM Votes v
    GROUP BY v.UserId
),
UserAggregate AS (
    SELECT
        u.Id           AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(bs.GoldBadges,   0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(cs.CommentsMade,    0) AS CommentsMade,
        COALESCE(cs.AvgCommentLength,0)::numeric(10,2) AS AvgCommentLength,
        COALESCE(vs.UpVotes,    0) AS UpVotes,
        COALESCE(vs.DownVotes,  0) AS DownVotes,
        COALESCE(vs.Favorites,  0) AS Favorites
    FROM Users u
    LEFT JOIN BadgeStats   bs ON bs.UserId   = u.Id
    LEFT JOIN CommentStats cs ON cs.UserId   = u.Id
    LEFT JOIN VoteStats    vs ON vs.UserId   = u.Id
),
RankedTags AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.CommentsMade,
        ua.AvgCommentLength,
        ua.UpVotes,
        ua.DownVotes,
        ua.Favorites,
        ast.Tag,
        ast.AnswersGiven,
        ast.TotalAnsScore,
        ROW_NUMBER() OVER (
            PARTITION BY ast.Tag
            ORDER BY ast.AnswersGiven DESC, ast.TotalAnsScore DESC
        ) AS TagRank
    FROM UserAggregate ua
    JOIN AnswerStats ast
      ON ast.UserId = ua.UserId
)
SELECT
    UserId,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    CommentsMade,
    AvgCommentLength,
    UpVotes,
    DownVotes,
    Favorites,
    Tag,
    AnswersGiven,
    TotalAnsScore,
    TagRank
FROM RankedTags
WHERE TagRank <= 3
ORDER BY Tag, TagRank;
