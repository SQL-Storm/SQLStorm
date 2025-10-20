WITH RecursiveUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Location,
        u.Reputation,
        u.CreationDate,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(vs.UpVotes), 0) AS TotalUpVotes,
        COALESCE(SUM(vs.DownVotes), 0) AS TotalDownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT
                PostId,
                SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
                SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
            FROM Votes v
            GROUP BY PostId
        ) vs ON p.Id = vs.PostId
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Location,
        u.Reputation,
        u.CreationDate
),

RankedPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        PHist.CreationDate AS LastBoost,
        (p.Score + p.ViewCount / 10.0) *
         POWER(
            0.99,
            EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - COALESCE(PHist.CreationDate, p.CreationDate))) / 3600
         ) AS PopularityScore
    FROM
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN LATERAL (
            SELECT MAX(ph.CreationDate) AS CreationDate
            FROM PostHistory ph
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 16, 50)
        ) PHist ON TRUE
    GROUP BY
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        PHist.CreationDate,
        p.CreationDate
)

SELECT
    rp.Id,
    rp.OwnerUserId,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.ViewCount,
    rp.PostTypeId,
    rp.LastBoost,
    rp.PopularityScore,
    rua.UserId,
    rua.DisplayName,
    rua.Location,
    rua.Reputation,
    rua.CreationDate,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.TotalUpVotes,
    rua.TotalDownVotes,
    rua.ReputationRank
FROM RankedPosts rp
LEFT JOIN RecursiveUserActivity rua ON rua.UserId = rp.OwnerUserId
ORDER BY rp.PopularityScore DESC, rp.Score DESC, rua.ReputationRank ASC;