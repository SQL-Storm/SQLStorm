-- {"query": "3188.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1399} 

/*  Complex benchmark query on the StackOverflow schema  */
WITH
    /* 1. Users with high reputation and recent activity */
    ActiveHighRep AS (
        SELECT
            u.Id                      AS UserId,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            u.LastAccessDate,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS RepRank
        FROM Users u
        WHERE u.Reputation > 50000
          AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '90 days'
    ),

    /* 2. Recent questions (last 30 days) with their tags exploded */
    RecentQuestions AS (
        SELECT
            p.Id                     AS QuestionId,
            p.Title,
            p.CreationDate,
            p.Score,
            p.ViewCount,
            p.FavoriteCount,
            unnest(string_to_array(trim(both '><' FROM p.Tags), '><')) AS Tag,
            p.OwnerUserId
        FROM Posts p
        WHERE p.PostTypeId = 1                     -- Question
          AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ),

    /* 3. Tag statistics for the recent period */
    TagStats AS (
        SELECT
            rq.Tag,
            COUNT(DISTINCT rq.QuestionId)                AS QuestionCount,
            SUM(rq.Score)                                 AS TotalScore,
            AVG(rq.ViewCount)                             AS AvgViews,
            COUNT(DISTINCT rq.OwnerUserId)                AS UniqueAuthors
        FROM RecentQuestions rq
        GROUP BY rq.Tag
    ),

    /* 4. Top tags by question count (limit 20) */
    TopTags AS (
        SELECT
            ts.Tag,
            ts.QuestionCount,
            ts.TotalScore,
            ts.AvgViews,
            ts.UniqueAuthors,
            ROW_NUMBER() OVER (ORDER BY ts.QuestionCount DESC) AS TagRank
        FROM TagStats ts
        ORDER BY ts.QuestionCount DESC
        LIMIT 20
    ),

    /* 5. Badge aggregation per user (only gold & silver) */
    UserBadges AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            COUNT(DISTINCT b.Name)               AS DistinctBadgeNames
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* 6. Vote summary per question (including up/down votes) */
    QuestionVotes AS (
        SELECT
            v.PostId                                 AS QuestionId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) -
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS NetScore
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE v.VoteTypeId IN (2, 3)               -- UpMod, DownMod
          AND v.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
        GROUP BY v.PostId
    ),

    /* 7. Correlated subquery to fetch the latest edit date for each question */
    LatestEdit AS (
        SELECT
            p.Id                                     AS QuestionId,
            MAX(ph.CreationDate)                     AS LastEditDate,
            MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate END) AS LastContentEdit
        FROM Posts p
        LEFT JOIN PostHistory ph ON ph.PostId = p.Id
        WHERE p.PostTypeId = 1
        GROUP BY p.Id
    )
SELECT
    ah.UserId,
    ah.DisplayName,
    ah.Reputation,
    ah.RepRank,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.DistinctBadgeNames,
    COALESCE(qv.UpVotes,0)                AS TotalUpVotes,
    COALESCE(qv.DownVotes,0)              AS TotalDownVotes,
    COALESCE(qv.NetScore,0)               AS NetVoteScore,
    COUNT(DISTINCT rq.QuestionId)         AS QuestionsAsked,
    AVG(rq.Score)                         AS AvgQuestionScore,
    MAX(rq.CreationDate)                 AS MostRecentQuestion,
    MIN(rq.CreationDate)                 AS FirstQuestionInPeriod,
    STRING_AGG(DISTINCT tt.Tag, ', ')     FILTER (WHERE tt.Tag IS NOT NULL) AS TopTags,
    MAX(le.LastEditDate)                 AS MostRecentEdit,
    MAX(le.LastContentEdit)              AS MostRecentContentEdit
FROM ActiveHighRep ah
LEFT JOIN UserBadges ub
       ON ub.UserId = ah.UserId
LEFT JOIN Posts p
       ON p.OwnerUserId = ah.UserId
      AND p.PostTypeId = 1                           -- Only questions
LEFT JOIN RecentQuestions rq
       ON rq.QuestionId = p.Id
LEFT JOIN QuestionVotes qv
       ON qv.QuestionId = p.Id
LEFT JOIN TopTags tt
       ON tt.Tag = rq.Tag
LEFT JOIN LatestEdit le
       ON le.QuestionId = p.Id
GROUP BY
    ah.UserId,
    ah.DisplayName,
    ah.Reputation,
    ah.RepRank,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.DistinctBadgeNames,
    qv.UpVotes,
    qv.DownVotes,
    qv.NetScore
HAVING COUNT(DISTINCT rq.QuestionId) >= 5
ORDER BY ah.RepRank
LIMIT 50;
