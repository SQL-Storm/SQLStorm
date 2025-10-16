-- {"query": "1562.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1494} 
with RankedPosts as (
  select
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName as Owner_name,
    row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn,
    case when p.AcceptedAnswerId is not null and a.Score is not null then a.Score else 0 end as AcceptedAnswerScore,
    coalesce(p.FavoriteCount, 0) as FavoriteCount,
    coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  left join Posts a on p.AcceptedAnswerId = a.Id
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1  
),
UserBadgesAggregate as (
  select
    b.UserId,
    count(case when Class=1 then 1 end) as GoldBadges,
    count(case when Class=2 then 1 end) as SilverBadges,
    count(case when Class=3 then 1 end) as BronzeBadges,
    string_agg(distinct b.Name, ', ') as BadgeNames
  from Badges b
  group by b.UserId
),
PostCommentAggregates as (
  select
    c.PostId,
    count(*) filter (where c.Text ilike '%help%') as HelpMentions,
    avg(c.Score) as AvgCommentScore,
    bool_or(c.Score > 5) as AnyHighScoreComment,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
RecursiveTagParts as (
  select
    p.Id,
    regexp_split_to_table(trim(both '<>' from p.Tags), E'><) as Tag
  from Posts p
  where p.Tags is not null
),

TopUserPosts as (
  select rp.*
  from RankedPosts rp
  where rn = 1 and Score > 
       (
        select avg(Score) from RankedPosts where OwnerUserId = (
          select kv.Id from Users kv order by kv.Reputation desc limit 1
        )
       )
),

ClosedPostsDue toRecentCloses as (
 select ph.PostId, max(ph.CreationDate) as LastCloseDate
 from PostHistory ph
 where ph.PostHistoryTypeId = 10  -- Post Closed
 group by ph.PostId
 HAVING max(ph.CreationDate) > current_date - interval '30 day'
),

ComplexUserPostAggregates as (
  select 
    u.Id as UserId,
    count(DISTINCT p.Id) as QuestionsAnswered,
    sum(case when p.Score > 5 then 1 else 0 end) as HighScoringAnswers,
    max(p.ViewCount) filter (where p.PostTypeId = 1) as MaxViewCountQ,
    coalesce(uba.GoldBadges,0) as GoldBadges,
    coalesce(uba.SilverBadges,0) as SilverBadges,
    coalesce(uba.BronzeBadges,0) as BronzeBadges,
    cea.HelpMentions,
    cea.AvgCommentScore,
    cea.AnyHighScoreComment,
    closedposts.LastCloseDate,
    row_number() over (partition by u.Location 
                                  order by count(p.Id) desc NULLS LAST) as rn_by_loc
  from Users u
  left join Posts p on p.OwnerUserId = u.Id 
       and p.PostTypeId in (1,2)
  left join UserBadgesAggregate uba on uba.UserId = u.Id
  left join PostCommentAggregates cea on cea.PostId = p.Id
  left join ClosedPostsDue toRecentCloses closedposts on closedposts.PostId = p.Id
  group by 
    u.Id, uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges, 
    cea.HelpMentions, cea.AvgCommentScore, cea.AnyHighScoreComment, closedposts.LastCloseDate, u.Location
),

AbilitiesAndVotes as (
  select distinct
    forces.AssociateId as UserId,
    string_agg(DISTINCT vt.Name, ', ' order by lt.Name) over (partition by forces.AssociateId)  as VoteTypesCast,  
    sum(u.Reputation) over (partition by forces.AssociateId) as AggregatedReputation,    
    sum(case when vt.Name in ('UpMod', 'AcceptedByOriginator') then 1 else 0 end) over (partition by forces.AssociateId) as PositiveVoteCount
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  join Posts p on p.Id = v.PostId
  left join Users u on u.Id = v.UserId 
  left join Users forces on forces.Id = v.UserId
  left join LinkTypes lt on lt.Id = v.VoteTypeId 
  where v.UserId is not null
)

select 
  cu.UserId,
  cu.GoldBadges,
  cu.SilverBadges,
  cu.BronzeBadges,
  cu.QuestionsAnswered,
  cu.HighScoringAnswers,
  concat_ws(' ~ '::text, substring(max_title,1,100), '% interaction') as ExampleTitleSnippet,
  navx.VoteTypesCast,
  max(cu.MaxViewCountQ) as ViewMania,
  coalesce(to_char(cu.LastCloseDate, 'YYYY-MM-DD'), 'never closed') as CloseStatus,
  border_tag.SubtagRank,
  upper(gt.Tag) as TopUpperCasePopularTag
from ComplexUserPostAggregates cu
left join (
  select rp.Id, max(rp.Title) over() as max_title
  from RankedPosts rp 
  where rp.rn = 1
) expt on expt.Id = (
  select Id from RankedPosts instalaciones
  where instalaciones.OwnerUserId = cu.UserId
  order by instalaciones.Score desc nulls last
  limit 1
)
left join AbilitiesAndVotes navx on navx.UserId = cu.UserId
left join (
    select distinct Tag, dense_rank() over(partition by Id order by count desc nulls last) as SubtagRank
    from (
      select pst.PersonId as Id, Tag, count(*) as count
      from RecursiveTagParts pst
      group by pst.PersonId, Tag
    ) as ipcat
    limit 5
) border_tag on border_tag.Id = cu.UserId
left join RecursiveTagParts gt on gt.Id in (select Id from RankedPosts where RankedPosts.OwnerUserId = cu.UserId order by Rank() over(partition by Comments desc) desc limit 1)

where cu.rn_by_loc <= 10
  and (Score * COALESCE(Cache.QuantityDivisão, 1.5)) / greatest(cu.HighScoringAnswers, 1) between 5 and 1000 -- complicated predicate as calculation
order by cu.HighScoringAnswers desc nulls last, cu.GoldBadges desc, cu.QuestionsAnswered desc
limit 100;