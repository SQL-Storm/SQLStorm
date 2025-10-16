-- {"query": "1301.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 918} 
with recursive RecentUserPosts as (
    select u.Id as UserId, 
           u.DisplayName,
           p.Id as PostId,
           p.PostTypeId,
           p.Score,
           p.CreationDate,
           p.Title,
           p.Tags,
           p.AcceptedAnswerId,
           row_number() over (partition by u.Id order by p.CreationDate desc) as rn
      from Users u
      left join Posts p on p.OwnerUserId = u.Id
     where u.CreationDate < now() - interval '180 day'
),
FilteredPosts as (
    select * from RecentUserPosts where rn <= 5
),
TagCounts as (
    select fp.PostId,
           tag.value as Tag
      from FilteredPosts fp,
           lateral unnest(string_to_array(substring(fp.Tags from 2 for char_length(fp.Tags)-2), '><')) as tag(value)
),
UserTagSummary as (
    select UserId, Tag, count(*) as TagCount
      from TagCounts
     group by UserId, Tag
),
ClosedDuplicatePosts as (
    select ph.PostId, ph.CreationDate as CloseDate, crt.Name as CloseReason
      from PostHistory ph
      join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
     where ph.PostHistoryTypeId = 10 -- Post Closed
       and crt.Name ilike '%duplicate%'
),
AcceptedAnswerRanks as (
    select p.Id as QuestionId, a.Id as AnswerId, a.OwnerUserId as AnswererId,
           row_number() over (partition by p.Id order by a.Score desc, a.CreationDate) as AnswerRank
      from Posts p
      join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
     where p.PostTypeId = 1 
       and p.AcceptedAnswerId = a.Id
),
UsersWithBadgeRanks as (
    select b.UserId,
           b.Name as BadgeName,
           b.Class,
           row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
      from Badges b
),
CombinedUserStats as (
    select u.Id as UserId,
           u.DisplayName,
           coalesce(sum(fps.Score),0) as TotalScore,
           count(distinct fps.PostId) as PostCount,
           max(fps.CreationDate) as LastPostDate,
           count(distinct case when crp.PostId is not null then 1 end) as ClosedAsDuplicateCount,
           count(distinct case when aar.AnswerRank = 1 then 1 end) as AcceptedTopAnswerCount,
           max(uwbr.Class) as HighestBadgeClass
      from Users u
      left join FilteredPosts fps on fps.UserId = u.Id
      left join ClosedDuplicatePosts crp on crp.PostId = fps.PostId
      left join AcceptedAnswerRanks aar on aar.AnswererId = u.Id
      left join UsersWithBadgeRanks uwbr on uwbr.UserId = u.Id and uwbr.BadgeRank = 1
     group by u.Id, u.DisplayName
)
select cus.UserId,
       cus.DisplayName,
       cus.TotalScore,
       cus.PostCount,
       cus.LastPostDate,
       cus.ClosedAsDuplicateCount,
       cus.AcceptedTopAnswerCount,
       case cus.HighestBadgeClass
            when 1 then 'Gold'
            when 2 then 'Silver'
            when 3 then 'Bronze'
            else 'None'
       end as HighestBadge,
       uts.Tag,
       uts.TagCount
  from CombinedUserStats cus
  left join UserTagSummary uts on cus.UserId = uts.UserId
 where cus.PostCount > 2
   and (cus.HighestBadgeClass is null or cus.HighestBadgeClass <= 2)
union
select u.Id, u.DisplayName,
       0 as TotalScore,
       0 as PostCount,
       null as LastPostDate,
       0 as ClosedAsDuplicateCount,
       0 as AcceptedTopAnswerCount,
       'None' as HighestBadge,
       null as Tag,
       null as TagCount
  from Users u
 where not exists (select 1 from Posts p where p.OwnerUserId = u.Id)
order by HighestBadge desc nulls last, TotalScore desc, PostCount desc, UserId
limit 100;