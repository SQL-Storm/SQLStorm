-- {"query": "188.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1532} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        0 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 2
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (order by u.Reputation desc) as ReputationRank,
        avg(u.Reputation) over () as AvgReputation,
        max(u.Reputation) over () as MaxReputation
    from Users u
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = p.OwnerUserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = p.OwnerUserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = p.OwnerUserId and ubc_bronze.Class = 3
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
QuestionComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Comments c
    group by c.PostId
),
QuestionVotes as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
QuestionWithDetails as (
    select
        tq.*,
        coalesce(ans.TotalAnswers, 0) as TotalAnswers,
        coalesce(ans.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(ans.AnonymousAnswers, 0) as AnonymousAnswers,
        qcr.CloseReason,
        qcr.CloseDate,
        qc.CommentCount,
        qc.LastCommentDate,
        qc.Commenters,
        qv.UpVotes,
        qv.DownVotes,
        qv.Favorites
    from TopQuestions tq
    left join AnswerStats ans on ans.QuestionId = tq.Id
    left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
    left join QuestionComments qc on qc.PostId = tq.Id
    left join QuestionVotes qv on qv.PostId = tq.Id
),
RankedQuestions as (
    select
        qwd.*,
        rank() over (order by qwd.Score desc, qwd.ViewCount desc) as GlobalRank,
        dense_rank() over (partition by qwd.OwnerUserId order by qwd.Score desc) as UserScoreRank
    from QuestionWithDetails qwd
),
FilteredQuestions as (
    select *
    from RankedQuestions
    where GlobalRank <= 100
      and (CloseReason is null or CloseReason not in ('Duplicate', 'Off-topic'))
      and (Tags is not null and Tags like '%<sql>%')
),
FinalOutput as (
    select
        fq.Id as QuestionId,
        fq.Title,
        fq.OwnerUserId,
        fq.OwnerName,
        fq.OwnerReputation,
        fq.GoldBadges,
        fq.SilverBadges,
        fq.BronzeBadges,
        fq.Score,
        fq.ViewCount,
        fq.AnswerCount,
        fq.TotalAnswers,
        fq.AvgAnswerScore,
        fq.MaxAnswerScore,
        fq.AnonymousAnswers,
        fq.CloseReason,
        fq.CloseDate,
        fq.CommentCount,
        fq.LastCommentDate,
        fq.Commenters,
        fq.UpVotes,
        fq.DownVotes,
        fq.Favorites,
        fq.GlobalRank,
        fq.UserScoreRank,
        -- Complex string expression: extract first tag from Tags array
        split_part(substring(fq.Tags from 2 for length(fq.Tags) - 2), '><', 1) as FirstTag,
        -- Complex calculation: normalized score
        case when fq.ViewCount > 0 then round(cast(fq.Score as numeric) / fq.ViewCount, 4) else null end as ScorePerView,
        -- Null logic: if CloseDate is null, use LastActivityDate from Posts
        coalesce(fq.CloseDate, (select p.LastActivityDate from Posts p where p.Id = fq.Id)) as EffectiveCloseOrLastActivityDate
    from FilteredQuestions fq
)
select *
from FinalOutput
order by GlobalRank
limit 50;