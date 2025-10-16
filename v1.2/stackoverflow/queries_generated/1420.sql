-- {"query": "1420.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1121} 
with QuestionVoteStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        coalesce(sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)),0) as TotalBounty,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as rn
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 1 and p.CreationDate > current_date - interval '1 year'
      and p.Tags is not null
    group by p.Id, p.Title, p.OwnerUserId
),
QuestionBadges as (
    select 
        b.UserId,
        json_agg(distinct json_build_object('Badge',b.Name,'Date', b.Date, 'Class', b.Class)) as Badges
    from Badges b
    group by b.UserId
),
AcceptedAnswerDuration as (
    select
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        extract(epoch from (a.CreationDate - q.CreationDate))/3600 as HoursToAcceptedAnswer
    from Posts q
    inner join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and a.PostTypeId = 2
),
UserLatestAccess as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreation,
        max(ph.CreationDate) as LastPostEdit
    from Users u
    left join PostHistory ph on ph.UserId = u.Id and ph.PostId is not null
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostsWithDuplicates as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        array_agg(distinct case when lt.Name = 'Duplicate' then rp.Id else null end) filter (where lt.Name = 'Duplicate') as DuplicateQuestions
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join Posts rp on rp.Id = pl.RelatedPostId
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.CreationDate
)
select
    qvs.QuestionId,
    substr(qvs.Title, 1, 100) || case when length(qvs.Title) > 100 then '...' else '' end as ShortTitle,
    qs.DuplicateQuestions,
    qvs.UpVotes,
    qvs.DownVotes,
    qvs.TotalBounty,
    ab.CountMutualBadges,
    ab.BadgeDetails,
    ac.HoursToAcceptedAnswer,
    ula.DisplayName as OwnerDisplayName,
    ula.Reputation,
    coalesce(cl.Name, 'No close record') as LastCloseReason,
    case 
        when qvs.UpVotes + qvs.DownVotes = 0 then null
        else round(qvs.UpVotes * 1.0 / (qvs.UpVotes + qvs.DownVotes)::float, 4)
    end as UpvoteRatio,
    rank() over (partition by ula.Reputation > 100000 order by qvs.TotalBounty desc nulls last) as BountyRanking,
    datediff('day', qvs.lastedit, current_date) as DaysSinceLastEdit
from QuestionVoteStats qvs
left join PostsWithDuplicates qs on qs.Id = qvs.QuestionId
left join AcceptedAnswerDuration ac on ac.QuestionId = qvs.QuestionId
left join UserLatestAccess ula on ula.UserId = qvs.OwnerUserId
left join (
    select ub.UserId, count(b.Id) as CountMutualBadges, min(b.Name) as FirstBadge,
        json_agg(json_build_object('BadgeName', b.Name, 'Class', b.Class, 'ClassDescr',
                case b.Class when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Unknown' end)) Badges() as BadgeDetails
    from Badges b
    join Users ub on ub.Id = b.UserId
    where b.Class in (1,2) and ub.Reputation > 10000
    group by ub.UserId
) ab on ab.UserId = qvs.OwnerUserId
left join (
    select ph.PostId, crt.Name
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
      and ph.CreationDate = (
          select max(CreationDate)
          from PostHistory ph2
          where ph2.PostId = ph.PostId and ph2.PostHistoryTypeId = 10
      )
) cl on cl.PostId = qvs.QuestionId
where qvs.rn = 1
order by ula.Reputation desc nulls last, qvs.TotalBounty desc nulls last
limit 100;