-- {"query": "2600.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1544} 

with RecursiveUserReputationHistory as (
    select
        u.Id as UserId,
        u.Reputation as Reputation,
        u.CreationDate as EventDate,
        1 as Level
    from Users u
    union all
    select
        ph.UserId,
        cast(coalesce(u.Reputation, 0) + (case when ph.PostId is not null then
            coalesce(p.Score,0) else 0 end) 
            + (select coalesce(sum(v.BountyAmount),0) from Votes v where v.UserId = ph.UserId and v.CreationDate <= ph.CreationDate), int) as Reputation,
        ph.CreationDate,
        r.Level + 1
    from PostHistory ph
    join RecursiveUserReputationHistory r on ph.UserId = r.UserId and ph.CreationDate > r.EventDate
    left join Users u on u.Id = ph.UserId
    left join Posts p on p.Id = ph.PostId
    where ph.UserId is not null
    and r.Level < 5
),
TopTagsWithStats as (
    select 
        t.TagName,
        t.Count,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore
    from Tags t
    left join Posts p on p.Tags like '%<'||t.TagName||'>%'
    group by t.TagName, t.Count
    having count(distinct p.Id) > 100
),
RecentHighImpactQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        array_to_string(array_agg(coalesce(c.UserDisplayName, u.DisplayName) order by c.CreationDate desc limit 5), ', ') as RecentCommentators
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 10 and p.CreationDate > current_date - interval '30 days'
    group by p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount
),
AnswerRanks as (
    select 
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as Rank
    from Posts a
    where a.PostTypeId = 2
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
ClosedDuplicateQuestions as (
    select 
        ph.PostId,
        p.Title,
        ph.CreationDate as ClosedDate,
        pc.RelatedPostId as DuplicateOfPostId,
        p.Score,
        ct.Name as CloseReason,
        cpt.Name as LinkTypeName
    from PostHistory ph
    join Posts p on p.Id = ph.PostId
    join PostLinks pc on pc.PostId = ph.PostId and pc.LinkTypeId = 3
    join CloseReasonTypes ct on ct.Id::int = ph.Comment::int
    join LinkTypes cpt on cpt.Id = pc.LinkTypeId
    where ph.PostHistoryTypeId = 10 -- Post Closed
    and p.PostTypeId = 1
    and ct.Name ilike '%duplicate%'
),
FinalUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(ubc.GoldBadges,0) as GoldBadges,
        coalesce(ubc.SilverBadges,0) as SilverBadges,
        coalesce(ubc.BronzeBadges,0) as BronzeBadges,
        coalesce(ubc.TotalBadges,0) as TotalBadges,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as Questions,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as Answers,
        (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AvgAnswerScore,
        (select max(p.Score) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as MaxAnswerScore,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2) as UpVotesCast,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 3) as DownVotesCast
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    where u.Reputation > 1000
    order by u.Reputation desc
    limit 50
)

select 
    fq.Id as QuestionId,
    fq.Title,
    fq.CreationDate,
    fq.Score as QuestionScore,
    fq.ViewCount,
    fq.RecentCommentators,
    a.Id as TopAnswerId,
    a.Score as TopAnswerScore,
    a.OwnerUserId as TopAnswerUserId,
    u.DisplayName as TopAnswerUserDisplayName,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.TotalBadges,
    us.Reputation as AnswererReputation,
    tt.TagName,
    tt.QuestionCount,
    tt.AvgQuestionScore,
    tt.AnswerCount,
    tt.AvgAnswerScore,
    cd.CloseReason,
    cd.ClosedDate,
    cd.DuplicateOfPostId
from RecentHighImpactQuestions fq
left join AnswerRanks a on a.ParentId = fq.Id and a.Rank = 1
left join FinalUserStats us on us.UserId = a.OwnerUserId
left join Users u on u.Id = a.OwnerUserId
left join LATERAL (
    select unnest(string_to_array(coalesce(fq.Title, ''), ' ')) as TagName
) tags on true
left join TopTagsWithStats tt on tt.TagName = tags.TagName
left join ClosedDuplicateQuestions cd on cd.PostId = fq.Id
where (tt.AvgAnswerScore is null or tt.AvgAnswerScore >= 0)
and (cd.CloseReason is null or cd.CloseReason not ilike '%off-topic%')
order by fq.Score desc, fq.ViewCount desc
limit 100;
