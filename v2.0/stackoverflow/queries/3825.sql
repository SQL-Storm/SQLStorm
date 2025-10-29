-- {"query": "3825.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2769}
WITH
    TopUsers AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(SUM(p.Score), 0) AS TotalPostScore,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) AS ScoreRank
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
        HAVING COUNT(p.Id) > 0
    ),
    UserBadges AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            STRING_AGG(b.Name, ', ' ORDER BY b.Name) AS BadgeNames
        FROM Badges b
        GROUP BY b.UserId
    ),
    RecentVotes AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
            MAX(v.CreationDate) AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '30 days')
        GROUP BY v.PostId
    ),
    TagPopularity AS (
        SELECT
            t.TagName,
            t.Count AS TagUseCount,
            COALESCE(e.ExcerptLength, 0) AS ExcerptLength,
            COALESCE(w.WikiLength, 0) AS WikiLength
        FROM Tags t
        LEFT JOIN LATERAL (
            SELECT LENGTH(p.Body) AS ExcerptLength
            FROM Posts p
            WHERE p.Id = t.ExcerptPostId
            LIMIT 1
        ) e ON TRUE
        LEFT JOIN LATERAL (
            SELECT LENGTH(p.Body) AS WikiLength
            FROM Posts p
            WHERE p.Id = t.WikiPostId
            LIMIT 1
        ) w ON TRUE
        WHERE t.IsModeratorOnly = FALSE
    ),
    ClosedDuplicatePairs AS (
        SELECT
            ph1.PostId AS ClosedPostId,
            ph2.PostId AS DuplicateOfPostId,
            ph1.CreationDate AS ClosedDate,
            ph2.CreationDate AS DuplicateDate
        FROM PostHistory ph1
        JOIN PostHistoryTypes pht1 ON pht1.Id = ph1.PostHistoryTypeId
        JOIN PostHistory ph2 ON ph2.Comment = ph1.Comment
            AND ph2.PostHistoryTypeId = 3
        JOIN PostHistoryTypes pht2 ON pht2.Id = ph2.PostHistoryTypeId
        WHERE pht1.Name = 'Post Closed'
          AND ph1.Comment LIKE '%101%'
    )
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPostScore,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.ScoreRank,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    ub.BadgeNames,
    COALESCE(rv.UpVotes, 0) AS RecentUpVotes,
    COALESCE(rv.DownVotes, 0) AS RecentDownVotes,
    rv.LastVoteDate,
    STRING_AGG(tp.TagName, '; ') AS TopTags,
    (SELECT c.Text
     FROM Comments c
     JOIN Posts p ON p.Id = c.PostId
     WHERE p.OwnerUserId = tu.Id
       AND p.PostTypeId = 1
     ORDER BY p.Score DESC NULLS LAST, c.CreationDate DESC
     LIMIT 1) AS LatestHighScoreQuestionComment,
    CASE
        WHEN cd.ClosedPostId IS NOT NULL THEN 'Closed as duplicate of ' || CAST(cd.DuplicateOfPostId AS VARCHAR)
        ELSE 'Active'
    END AS ClosureStatus
FROM TopUsers tu
FULL OUTER JOIN UserBadges ub ON ub.UserId = tu.Id
LEFT JOIN RecentVotes rv ON rv.PostId = (
    SELECT p.Id
    FROM Posts p
    WHERE p.OwnerUserId = tu.Id
      AND p.PostTypeId = 2
    ORDER BY p.Score DESC NULLS LAST
    LIMIT 1
)
LEFT JOIN LATERAL (
    SELECT tp.TagName, tp.TagUseCount
    FROM TagPopularity tp
    WHERE tp.TagUseCount > 0
    ORDER BY tp.TagUseCount DESC
    LIMIT 5
) tp ON TRUE
LEFT JOIN ClosedDuplicatePairs cd ON cd.ClosedPostId = (
    SELECT p.Id
    FROM Posts p
    WHERE p.OwnerUserId = tu.Id
      AND p.PostTypeId = 1
    ORDER BY p.CreationDate DESC
    LIMIT 1
)
GROUP BY
    tu.Id, tu.DisplayName, tu.Reputation, tu.TotalPostScore,
    tu.QuestionCount, tu.AnswerCount, tu.ScoreRank,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.BadgeNames,
    rv.UpVotes, rv.DownVotes, rv.LastVoteDate,
    cd.ClosedPostId, cd.DuplicateOfPostId, cd.ClosedDate, cd.DuplicateDate
ORDER BY tu.ScoreRank
LIMIT 100;