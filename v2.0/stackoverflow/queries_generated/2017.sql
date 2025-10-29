-- {"query": "2017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1580} 
with RecursiveLinkedPosts as (
    select pl.PostId, pl.RelatedPostId, 1 as depth
    from PostLinks pl
    where pl.LinkTypeId = 1
  union all
    select rlp.PostId, pl.RelatedPostId, rlp.depth + 1
    from RecursiveLinkedPosts rlp
    join PostLinks pl on pl.PostId = rlp.RelatedPostId and pl.LinkTypeId = 1
    where rlp.depth < 3
), UserBadgeStats as (
    select 
      u.Id as UserId,
      u.DisplayName,
      count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
      count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
      count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
      max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
), PostVoteSummary as (
    select 
      p.Id as PostId,
      p.PostTypeId,
      p.OwnerUserId,
      coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotes,
      coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotes,
      coalesce(sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end),0) as TotalBounty,
      max(v.CreationDate) as LastVoteDate
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId
), QuestionAnswerStats as (
    select 
      q.Id as QuestionId,
      q.Title,
      q.CreationDate as QuestionDate,
      q.OwnerUserId,
      count(distinct a.Id) as AnswerCount,
      avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore,
      max(a.Score) filter (where a.Score is not null) as MaxAnswerScore,
      max(a.LastActivityDate) as LastAnswerActivityDate
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
), RankedPosts as (
    select 
      p.*,
      row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as UserPostRank,
      dense_rank() over (order by p.Score desc) as GlobalScoreRank
    from Posts p
    where p.PostTypeId in (1,2)
), ComplexFilteredPosts as (
    select rp.*
    from RankedPosts rp
    inner join Users u on u.Id = rp.OwnerUserId
    where 
      rp.UserPostRank <= 5
      and (u.Reputation > 1000 or exists (
          select 1 from Badges b where b.UserId = u.Id and b.Class = 1
      ))
      and (
        rp.Title ilike '%SQL%'
        or rp.Body ilike '%join%'
        or rp.Tags ilike '%<sql>%'
      )
      and (
        rp.Score > coalesce((select avg(Score) from Posts p2 where p2.OwnerUserId = rp.OwnerUserId),0)
        or rp.ViewCount > 1000
      )
), SubstringTagExtraction as (
    select 
      p.Id,
      unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as SingleTag
    from Posts p
    where p.Tags is not null and char_length(p.Tags) > 2 and p.PostTypeId = 1
), CorrelatedSubQueryLatestComment as (
    select 
      p.Id as PostId,
      (select c.Text from Comments c where c.PostId = p.Id order by c.CreationDate desc limit 1) as LatestCommentText,
      (select c.UserDisplayName from Comments c where c.PostId = p.Id order by c.CreationDate desc limit 1) as LatestCommenter,
      (select c.CreationDate from Comments c where c.PostId = p.Id order by c.CreationDate desc limit 1) as LatestCommentDate
    from Posts p
    where p.PostTypeId = 1
), BadgeWeightedScore as (
    select 
      u.Id as UserId,
      coalesce(sum(p.Score * 
        case b.Class 
          when 1 then 3 
          when 2 then 2 
          when 3 then 1 
          else 0 
        end), 0) as WeightedScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Badges b on b.UserId = u.Id
    group by u.Id
)
select 
  cfp.Id as PostId,
  cfp.Title,
  cfp.Score,
  cfp.ViewCount,
  u.DisplayName as OwnerName,
  u.Reputation,
  ubs.GoldBadges,
  ubs.SilverBadges,
  ubs.BronzeBadges,
  pvs.UpVotes,
  pvs.DownVotes,
  pvs.TotalBounty,
  qas.AnswerCount,
  coalesce(qas.AvgAnswerScore,0) as AvgAnswerScore,
  coalesce(qas.MaxAnswerScore,0) as MaxAnswerScore,
  csq.LatestCommentText,
  csq.LatestCommenter,
  csq.LatestCommentDate,
  string_agg(distinct st.SingleTag, ', ') as TagsAggregated,
  rlp.depth as LinkedDepth,
  coalesce(bws.WeightedScore,0) as UserBadgeWeightedScore
from ComplexFilteredPosts cfp
left join Users u on u.Id = cfp.OwnerUserId
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join PostVoteSummary pvs on pvs.PostId = cfp.Id
left join QuestionAnswerStats qas on qas.QuestionId = cfp.Id
left join SubstringTagExtraction st on st.Id = cfp.Id
left join CorrelatedSubQueryLatestComment csq on csq.PostId = cfp.Id
left join RecursiveLinkedPosts rlp on rlp.PostId = cfp.Id and rlp.depth = 1
left join BadgeWeightedScore bws on bws.UserId = u.Id
where cfp.Score > 0
group by cfp.Id, cfp.Title, cfp.Score, cfp.ViewCount, u.DisplayName, u.Reputation, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, pvs.UpVotes, pvs.DownVotes, pvs.TotalBounty, qas.AnswerCount, qas.AvgAnswerScore, qas.MaxAnswerScore, csq.LatestCommentText, csq.LatestCommenter, csq.LatestCommentDate, rlp.depth, bws.WeightedScore
order by cfp.Score desc, qas.AnswerCount desc, u.Reputation desc
limit 50;