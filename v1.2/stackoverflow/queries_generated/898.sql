-- {"query": "898.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1357} 
with RecursiveCTE as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate) as rn,
        1 as level
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null

    union all

    select 
        p2.Id,
        p2.PostTypeId,
        p2.OwnerUserId,
        p2.CreationDate,
        p2.Title,
        p2.Score,
        p2.ViewCount,
        p2.Tags,
        rc.rn + 1,
        rc.level + 1
    from Posts p2
    join RecursiveCTE rc on rc.OwnerUserId = p2.OwnerUserId and p2.CreationDate > rc.CreationDate
    where p2.PostTypeId = 1 and p2.OwnerUserId is not null and rc.level < 3
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
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        avg(p.Score) over (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row) as AvgScoreUpToNow
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    left join Posts p on p.OwnerUserId = u.Id
),
CloseReasonUsage as (
    select 
        crt.Id as CloseReasonId,
        crt.Name as CloseReasonName,
        count(ph.Id) as CloseCount
    from CloseReasonTypes crt
    left join PostHistory ph on ph.PostHistoryTypeId = 10 and ph.Comment = cast(crt.Id as varchar)
    group by crt.Id, crt.Name
),
Duplicates as (
    select distinct pl.PostId
    from PostLinks pl
    where pl.LinkTypeId = 3
),
QuestionsWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesCount,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesCount,
        string_agg(distinct u.DisplayName, ', ') as Answerers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = a.Id and v.VoteTypeId in (2,3)
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
),
ComplexFilteredQuestions as (
    select 
        qwa.QuestionId,
        qwa.Title,
        urw.DisplayName,
        qwa.AnswerCount,
        qwa.MaxAnswerScore,
        qwa.UpVotesCount,
        qwa.DownVotesCount,
        urw.GoldBadges,
        urw.SilverBadges,
        urw.BronzeBadges,
        urw.AvgScoreUpToNow,
        cr.CloseReasonName,
        case when d.PostId is not null then 1 else 0 end as IsDuplicate
    from QuestionsWithAnswers qwa
    join UserReputationWindow urw on urw.UserId = qwa.OwnerUserId
    left join PostHistory ph on ph.PostId = qwa.QuestionId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
    left join CloseReasonUsage cr on cr.CloseReasonId = crt.Id
    left join Duplicates d on d.PostId = qwa.QuestionId
    where 
        (qwa.AnswerCount > 2 or qwa.MaxAnswerScore > 5) 
        and urw.Reputation > 1000
        and (qwa.Title ilike '%performance%' or qwa.Title ilike '%benchmark%')
        and (cr.CloseReasonName is null or cr.CloseReasonName <> 'Duplicate')
        and (d.PostId is null)
)
select 
    cfq.QuestionId,
    cfq.Title,
    cfq.DisplayName as OwnerName,
    cfq.AnswerCount,
    cfq.MaxAnswerScore,
    cfq.UpVotesCount,
    cfq.DownVotesCount,
    cfq.GoldBadges,
    cfq.SilverBadges,
    cfq.BronzeBadges,
    cfq.AvgScoreUpToNow,
    coalesce(cru.CloseCount,0) as TotalClosed,
    case when cfq.IsDuplicate = 1 then 'Yes' else 'No' end as DuplicateFlag,
    substring(cast(cast(cfq.QuestionId as bigint)*random() as text),1,15) as RandomStr,
    case when cfq.UpVotesCount > cfq.DownVotesCount then 'Positive' else 'NegativeOrNeutral' end as VoteSentiment
from ComplexFilteredQuestions cfq
left join CloseReasonUsage cru on cru.CloseReasonName = cfq.CloseReasonName
order by cfq.AvgScoreUpToNow desc, cfq.MaxAnswerScore desc
limit 100;