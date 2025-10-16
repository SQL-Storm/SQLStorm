-- {"query": "118.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2011} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and r.Level < 3
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as RepRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByKnownUsers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
QuestionVotes as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
QuestionCommentsCount as (
    select
        c.PostId,
        count(*) as CommentCount
    from Comments c
    group by c.PostId
),
QuestionDetails as (
    select
        tq.Id,
        tq.Title,
        tq.OwnerUserId,
        tq.OwnerName,
        tq.Score,
        tq.ViewCount,
        tq.CreationDate,
        tq.Tags,
        tq.AcceptedAnswerId,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(ans.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(ans.AnsweredByKnownUsers,0) as AnsweredByKnownUsers,
        coalesce(qv.UpVotes,0) as UpVotes,
        coalesce(qv.DownVotes,0) as DownVotes,
        coalesce(qv.Favorites,0) as Favorites,
        coalesce(qc.CommentCount,0) as CommentCount,
        qcr.CloseReasonName,
        qcr.CloseDate,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        ur.Reputation,
        ur.Location,
        ur.RepRank,
        row_number() over (partition by tq.OwnerUserId order by tq.Score desc) as QuestionRankByUser
    from TopQuestions tq
    left join AnswerStats ans on ans.QuestionId = tq.Id
    left join QuestionVotes qv on qv.PostId = tq.Id
    left join QuestionCommentsCount qc on qc.PostId = tq.Id
    left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
    left join UserReputationStats ur on ur.UserId = tq.OwnerUserId
),
AcceptedAnswerDetails as (
    select
        p.Id,
        p.ParentId as QuestionId,
        p.Score as AnswerScore,
        p.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 2
),
FinalResults as (
    select
        qd.Id as QuestionId,
        qd.Title,
        qd.OwnerUserId,
        qd.OwnerName,
        qd.Score as QuestionScore,
        qd.ViewCount,
        qd.CreationDate as QuestionCreationDate,
        qd.Tags,
        qd.AnswerCount,
        qd.AvgAnswerScore,
        qd.MaxAnswerScore,
        qd.AnsweredByKnownUsers,
        qd.UpVotes,
        qd.DownVotes,
        qd.Favorites,
        qd.CommentCount,
        qd.CloseReasonName,
        qd.CloseDate,
        qd.GoldBadges,
        qd.SilverBadges,
        qd.BronzeBadges,
        qd.Reputation as OwnerReputation,
        qd.Location,
        qd.RepRank,
        qd.QuestionRankByUser,
        a.AnswerScore as AcceptedAnswerScore,
        a.AnswerCreationDate as AcceptedAnswerCreationDate,
        a.AnswerOwnerName as AcceptedAnswerOwnerName,
        a.AnswerOwnerReputation as AcceptedAnswerOwnerReputation,
        -- Complex string expression: concatenation of tags with user location and badge summary
        concat_ws(' | ',
            coalesce(qd.Tags, 'NoTags'),
            coalesce(qd.Location, 'UnknownLocation'),
            concat('Badges(G/S/B): ', qd.GoldBadges, '/', qd.SilverBadges, '/', qd.BronzeBadges)
        ) as TagLocationBadgeSummary,
        -- Window function: rank of question score within location
        rank() over (partition by qd.Location order by qd.Score desc nulls last) as LocationScoreRank,
        -- Complex predicate: flag questions with high score but no accepted answer and many answers
        case
            when qd.AcceptedAnswerId is null and qd.Score > 50 and qd.AnswerCount > 5 then 1
            else 0
        end as HighScoreNoAcceptedAnswerFlag,
        -- Correlated subquery: count of distinct users who answered this question
        (
            select count(distinct OwnerUserId)
            from Posts p2
            where p2.PostTypeId = 2 and p2.ParentId = qd.Id and p2.OwnerUserId is not null
        ) as DistinctAnswerersCount
    from QuestionDetails qd
    left join AcceptedAnswerDetails a on a.Id = qd.AcceptedAnswerId
)
select
    fr.QuestionId,
    fr.Title,
    fr.OwnerName,
    fr.OwnerReputation,
    fr.Location,
    fr.Score as QuestionScore,
    fr.ViewCount,
    fr.AnswerCount,
    fr.AvgAnswerScore,
    fr.MaxAnswerScore,
    fr.AnsweredByKnownUsers,
    fr.UpVotes,
    fr.DownVotes,
    fr.Favorites,
    fr.CommentCount,
    fr.CloseReasonName,
    fr.CloseDate,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.AcceptedAnswerScore,
    fr.AcceptedAnswerCreationDate,
    fr.AcceptedAnswerOwnerName,
    fr.AcceptedAnswerOwnerReputation,
    fr.TagLocationBadgeSummary,
    fr.LocationScoreRank,
    fr.HighScoreNoAcceptedAnswerFlag,
    fr.DistinctAnswerersCount
from FinalResults fr
where fr.Location is not null
order by fr.LocationScoreRank, fr.QuestionScore desc
limit 100;