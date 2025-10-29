-- {"query": "2812.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1568} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired, 1 as Level
    from Tags t
    where t.IsRequired = 1
    union all
    select t2.Id, t2.TagName, t2.Count, t2.ExcerptPostId, t2.WikiPostId, t2.IsModeratorOnly, t2.IsRequired, r.Level + 1
    from Tags t2
    join RecursiveTagHierarchy r on t2.ExcerptPostId = r.WikiPostId
    where t2.IsRequired = 1 and r.Level < 5
), 
QuestionAnswerStats as (
    select p.Id as QuestionId,
           p.Title,
           p.OwnerUserId,
           p.CreationDate,
           p.Score as QuestionScore,
           p.ViewCount,
           p.AnswerCount,
           (select count(*) from Posts a where a.ParentId = p.Id and a.Score > 0) as PositiveAnswersCount,
           (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as QuestionUpVotes,
           (select count(*) from Comments c where c.PostId = p.Id) as CommentsCount,
           u.Reputation as OwnerReputation,
           u.DisplayName as OwnerName,
           u.Location,
           row_number() over (partition by p.Tags order by p.CreationDate desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.CreationDate > current_date - interval '365 days'
),
AcceptedAnswers as (
    select p.Id as AnswerId,
           p.ParentId as QuestionId,
           p.Score as AnswerScore,
           p.OwnerUserId,
           u.DisplayName as AnswerOwner,
           p.CreationDate as AnswerDate,
           count(v.Id) filter (where v.VoteTypeId=2) as AnswerUpVotes,
           count(v.Id) filter (where v.VoteTypeId=3) as AnswerDownVotes,
           case when p.Score > 10 then 'HighScore' else 'LowScore' end as ScoreCategory
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 2 and p.Id in (select AcceptedAnswerId from Posts where PostTypeId = 1)
    group by p.Id, p.ParentId, p.Score, p.OwnerUserId, u.DisplayName, p.CreationDate
),
UserBadgeSummary as (
    select b.UserId,
           count(*) as TotalBadges,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
           bool_or(b.TagBased) as HasTagBadges
    from Badges b
    group by b.UserId
),
UserActivityWindow as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.LastAccessDate,
           sum(case when p.PostTypeId = 1 then 1 else 0 end) over w as QuestionsPosted,
           sum(case when p.PostTypeId = 2 then 1 else 0 end) over w as AnswersPosted,
           sum(coalesce(v.VoteTypeId = 2::int,0)) over w as UpVotesGiven,
           sum(coalesce(v.VoteTypeId = 3::int,0)) over w as DownVotesGiven
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    window w as (partition by u.Id order by u.CreationDate rows between unbounded preceding and current row)
),
ClosedQuestionsWithReasons as (
    select ph.PostId,
           p.Title,
           p.CreationDate,
           ph.CreationDate as CloseDate,
           crt.Name as CloseReason,
           u.DisplayName as CloserName,
           ph.UserId as CloserUserId
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
ComplexSearch as (
    select qas.QuestionId, qas.Title, qas.OwnerName, qas.OwnerReputation,
           acc.AnswerId, acc.AnswerScore, acc.AnswerOwner, acc.AnswerUpVotes, acc.ScoreCategory,
           ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.HasTagBadges,
           case when cq.PostId is not null then 1 else 0 end as IsClosed,
           coalesce(cq.CloseReason, 'Open') as CloseReason,
           coalesce(cq.CloserName, 'N/A') as CloserName,
           qas.CreationDate as QuestionCreated,
           acc.AnswerDate,
           case
             when acc.AnswerDate is not null and qas.CreationDate is not null then 
                extract(epoch from (acc.AnswerDate - qas.CreationDate))/3600
             else null end as HoursToAnswer
    from QuestionAnswerStats qas
    left join AcceptedAnswers acc on acc.QuestionId = qas.QuestionId
    left join UserBadgeSummary ubs on ubs.UserId = qas.OwnerUserId
    left join ClosedQuestionsWithReasons cq on cq.PostId = qas.QuestionId
    where qas.rn <= 1000
)
select cs.QuestionId, 
       cs.Title, 
       cs.OwnerName, 
       cs.OwnerReputation, 
       cs.TotalBadges, 
       cs.GoldBadges, 
       cs.AnswerId, 
       cs.AnswerScore, 
       cs.AnswerOwner, 
       cs.AnswerUpVotes, 
       cs.ScoreCategory,
       cs.IsClosed, 
       cs.CloseReason, 
       cs.CloserName, 
       cs.HoursToAnswer,
       substring(cast(cs.Title as varchar), 1, 50) || '...' as ShortTitle,
       case 
           when cs.OwnerReputation > 10000 then 'Veteran'
           when cs.OwnerReputation between 1000 and 9999 then 'Intermediate'
           else 'Newbie' 
       end as UserLevel,
       json_build_object(
         'Gold', cs.GoldBadges, 
         'Silver', cs.SilverBadges, 
         'Bronze', cs.BronzeBadges
       ) as BadgeCounts
from ComplexSearch cs
where 
    (cs.IsClosed = 0 or cs.CloseReason not like '%Duplicate%')
    and (cs.AnswerUpVotes is null or cs.AnswerUpVotes > 2)
order by cs.OwnerReputation desc, cs.AnswerUpVotes desc nulls last, cs.HoursToAnswer asc nulls last
limit 100;