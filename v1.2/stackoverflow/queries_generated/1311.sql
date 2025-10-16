-- {"query": "1311.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 959} 
with RECURSIVE UserBadgeCTE as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        ROW_NUMBER() over (partition by u.Id order by b.Class, b.Date desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000 
      and b.Date > (current_date - interval '365 day')
  
), LatestPostPerUser as (
    select p.OwnerUserId, max(p.CreationDate) as LatestPostDate
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
), QuestionAnswerStats as (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        COALESCE((
          select count(*)
          from Posts a
          where a.PostTypeId = 2 and a.ParentId = p.Id
        ), 0) as AnswerCountComputed,
        p.Score as PostScore,
        p.ViewCount,
        COALESCE(suu.UpVotes,0) as UserUpVotes,
        COALESCE(sdu.DownVotes,0) as UserDownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostRank,
        p.Title,
        p.Tags
    from posts p
    left join Users su on su.Id = p.OwnerUserId
    left join Users suu on suu.Id = p.OwnerUserId
    left join Users sdu on sdu.Id = p.OwnerUserId
    where p.PostTypeId = 1 
      and p.CreationDate > (current_date - interval '180 day')
), DupCandidates as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
), TopTagsCTE as (
    select 
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag,  
        count(*) as TagUseCount
    from Posts p
    where p.Tags is not null and p.PostTypeId = 1
    group by Tag
    order by TagUseCount desc
    limit 10
), UserReputationChange as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        lag(u.Reputation) over (order by u.CreationDate) as PrevRep,
        ((u.Reputation - lag(u.Reputation) over (order by u.CreationDate))::float / NULLIF(extract(day from (u.LastAccessDate - u.CreationDate)), 0)) * 1000 as RepChangePer1000Days
    from Users u
    where u.Reputation > 0
)
select distinct 
    qs.PostId,
    qs.Title,
    qs.Tags,
    qs.AnswerCountComputed,
    qs.PostScore,
    qs.ViewCount,
    qb.BadgeName,
    qb.BadgeClass,
    pl_related.RelatedPostId as DuplicatePostId,
    pl_related.LinkTypeName,
    usr.DisplayName,
    usr.Reputation,
    lpost.LatestPostDate,
    utrc.RepChangePer1000Days,
    tt.Tag as TopUsedTag
from QuestionAnswerStats qs
left join UserBadgeCTE qb on qb.UserId = qs.OwnerUserId and qb.BadgeRank <= 3
left join Users usr on usr.Id = qs.OwnerUserId
left join LatestPostPerUser lpost on lpost.OwnerUserId = qs.OwnerUserId
left join DupCandidates pl_related on pl_related.PostId = qs.PostId
left join UserReputationChange utrc on utrc.UserId = qs.OwnerUserId
left join TopTagsCTE tt on tt.Tag = ANY(string_to_array(substring(qs.Tags from 2 for length(qs.Tags) - 2), '><'))
where 
    (qs.PostScore > 5 or qs.AnswerCountComputed > 3 or qs.ViewCount > 5000)
    and (qb.BadgeClass is null or qb.BadgeClass <= 2)
order by 
    qs.PostScore desc nulls last,
    qs.AnswerCountComputed desc,
    utrc.RepChangePer1000Days desc nulls last
limit 100;