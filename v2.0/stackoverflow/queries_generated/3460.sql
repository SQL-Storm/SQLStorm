-- {"query": "3460.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2601} 

/*  Complex benchmarking query on the StackOverflow schema  */
WITH
/* --------------------------------------------------------------
   1. Basic per‑user statistics (questions, answers, badges, votes)
   -------------------------------------------------------------- */
UserStats AS (
    SELECT
        u.Id                                                            AS UserId,
        u.DisplayName                                                   AS DisplayName,
        u.Reputation                                                    AS Reputation,
        /* questions authored */
        (SELECT COUNT(*) FROM Posts p
            WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1)            AS QuestionCount,
        /* answers authored */
        (SELECT COUNT(*) FROM Posts p
            WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2)            AS AnswerCount,
        /* badge breakdown */
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        /* net vote score on all owned posts (up‑votes – down‑votes) */
        COALESCE((
            SELECT
                SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) -
                SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
            FROM Votes v
            JOIN Posts p ON p.Id = v.PostId
            WHERE p.OwnerUserId = u.Id
        ),0)                                                            AS NetVoteScore
    FROM Users u
    WHERE u.Reputation > 1000                     -- restrict to “active” users for the benchmark
),

/* --------------------------------------------------------------
   2. Tag meta‑information (including optional excerpt/wiki titles)
   -------------------------------------------------------------- */
TagInfo AS (
    SELECT
        t.Id                                   AS TagId,
        t.TagName                              AS TagName,
        t.Count                                AS TagUseCount,
        COALESCE(e.Title,'')                   AS ExcerptTitle,
        COALESCE(w.Title,'')                   AS WikiTitle
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),

/* --------------------------------------------------------------
   3. Per‑user activity per tag (questions, answers, vote tallies)
   -------------------------------------------------------------- */
UserTagActivity AS (
    SELECT
        us.UserId,
        ti.TagName,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)                               AS QuestionsWithTag,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)                               AS AnswersWithTag,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)                     AS UpVotesOnTagPosts,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)                     AS DownVotesOnTagPosts,
        ROW_NUMBER() OVER (PARTITION BY us.UserId ORDER BY
            COUNT(*) DESC)                                                    AS TagRank
    FROM UserStats us
    JOIN Posts p               ON p.OwnerUserId = us.UserId
    /* split the Tags column into separate tag strings */
    JOIN LATERAL regexp_split_to_table(p.Tags, '><') AS raw_tag(tag) ON TRUE
    JOIN TagInfo ti            ON ti.TagName = trim(both '<>' FROM raw_tag.tag)
    LEFT JOIN Votes v          ON v.PostId = p.Id
    GROUP BY us.UserId, ti.TagName
),

/* --------------------------------------------------------------
   4. Global ranking of users based on a weighted score
   -------------------------------------------------------------- */
TopUsers AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.NetVoteScore,
        /* weighted composite score */
        ( us.Reputation
          + us.NetVoteScore
          + us.GoldBadges   * 100
          + us.SilverBadges *  50
          + us.BronzeBadges *  10 )                                        AS CompositeScore,
        ROW_NUMBER() OVER (ORDER BY
            ( us.Reputation
              + us.NetVoteScore
              + us.GoldBadges   * 100
              + us.SilverBadges *  50
              + us.BronzeBadges *  10 ) DESC)                              AS GlobalRank
    FROM UserStats us
),

/* --------------------------------------------------------------
   5. Aggregate row for overall totals (used in UNION ALL later)
   -------------------------------------------------------------- */
AggregatedTotals AS (
    SELECT
        -1                                     AS GlobalRank,
        'TOTAL'                                AS DisplayName,
        SUM(QuestionCount)                     AS Reputation,          -- placeholder column alignment
        SUM(AnswerCount)                       AS QuestionCount,
        SUM(GoldBadges)                         AS AnswerCount,
        SUM(SilverBadges)                       AS GoldBadges,
        SUM(BronzeBadges)                       AS SilverBadges,
        SUM(NetVoteScore)                      AS BronzeBadges,
        NULL                                    AS UpVotesOnTagPosts   -- unused in total row
    FROM TopUsers
)

SELECT
    tu.GlobalRank,
    tu.DisplayName,
    tu.Reputation,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.NetVoteScore,
    COALESCE(uta.TagName,'(none)')            AS TopTag,
    uta.QuestionsWithTag,
    uta.AnswersWithTag,
    uta.UpVotesOnTagPosts,
    uta.DownVotesOnTagPosts
FROM TopUsers tu
LEFT JOIN LATERAL (
    SELECT
        uta1.TagName,
        uta1.QuestionsWithTag,
        uta1.AnswersWithTag,
        uta1.UpVotesOnTagPosts,
        uta1.DownVotesOnTagPosts
    FROM UserTagActivity uta1
    WHERE uta1.UserId = tu.UserId
    ORDER BY uta1.TagRank
    LIMIT 1
) uta ON TRUE
WHERE tu.GlobalRank <= 100                                 -- limit to top‑100 for the benchmark
UNION ALL
SELECT
    at.GlobalRank,
    at.DisplayName,
    at.Reputation,
    at.QuestionCount,
    at.AnswerCount,
    at.GoldBadges,
    at.SilverBadges,
    at.BronzeBadges,
    NULL        AS NetVoteScore,
    NULL        AS TopTag,
    NULL        AS QuestionsWithTag,
    NULL        AS AnswersWithTag,
    NULL        AS UpVotesOnTagPosts,
    NULL        AS DownVotesOnTagPosts
FROM AggregatedTotals at
ORDER BY GlobalRank;
