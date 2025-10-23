-- {"query": "624.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1201} 
with RecursiveUserBadges as (
    select u.Id as UserId,
           u.DisplayName,
           b.Name as BadgeName,
           b.Class,
           row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
      from Users u
      left join Badges b on u.Id = b.UserId
     where u.Reputation > 1000
),
RankedPosts as (
    select p.Id,
           p.PostTypeId,
           p.OwnerUserId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.Tags,
           p.Title,
           p.AcceptedAnswerId,
           dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as UserPostRank
      from Posts p
     where p.PostTypeId in (1, 2) and p.Score >= 0
),
TagExploded as (
    select p.Id as PostId,
           trim(tag) as Tag
      from Posts p,
           unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag
     where p.PostTypeId = 1
),
UserActivity as (
    select u.Id as UserId,
           count(distinct p.Id) as TotalPosts,
           count(distinct c.Id) as TotalComments,
           count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
           count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived,
           min(p.CreationDate) as FirstPostDate,
           max(p.LastActivityDate) as LastActivityDate
      from Users u
      left join Posts p on p.OwnerUserId = u.Id
      left join Comments c on c.UserId = u.Id
      left join Votes v on v.PostId = p.Id
     group by u.Id
),
DuplicateLinks as (
    select pl.PostId,
           pl.RelatedPostId,
           p1.Title as PostTitle,
           p2.Title as RelatedPostTitle
      from PostLinks pl
      join Posts p1 on pl.PostId = p1.Id
      join Posts p2 on pl.RelatedPostId = p2.Id
     where pl.LinkTypeId = 3
),
PostCloseReasons as (
    select ph.PostId,
           crt.Name as CloseReasonName,
           ph.CreationDate as CloseDate
      from PostHistory ph
      join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
     where ph.PostHistoryTypeId = 10
),
UserPostStats as (
    select p.OwnerUserId,
           count(*) as TotalAnswers,
           sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as AcceptedAnswersCount,
           avg(p.Score) as AvgScore,
           max(p.Score) as MaxScore,
           count(distinct t.Tag) as DistinctTagsCount
      from Posts p
      left join TagExploded t on p.Id = t.PostId
     where p.PostTypeId = 2
     group by p.OwnerUserId
)
select u.Id as UserId,
       u.DisplayName,
       ua.TotalPosts,
       ua.TotalComments,
       ua.UpVotesReceived,
       ua.DownVotesReceived,
       ua.FirstPostDate,
       ua.LastActivityDate,
       ups.TotalAnswers,
       ups.AcceptedAnswersCount,
       ups.AvgScore,
       ups.MaxScore,
       ups.DistinctTagsCount,
       string_agg(distinct db.BadgeName || ' (' || 
                  case db.Class when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Unknown' end || ')', ', ') as Badges,
       coalesce(pc.CloseReasonName, 'Open') as PostStatus,
       pc.CloseDate,
       dup.PostTitle as DuplicatePostTitle,
       dup.RelatedPostTitle as DuplicateOfTitle,
       rp.UserPostRank,
       case 
         when u.WebsiteUrl is not null and u.WebsiteUrl <> '' then 'Has Website'
         else 'No Website'
       end as WebsitePresence,
       case 
         when ua.TotalPosts > 0 then ua.UpVotesReceived::float / nullif(ua.TotalPosts,0)
         else null
       end as AvgUpVotesPerPost
  from Users u
  left join UserActivity ua on u.Id = ua.UserId
  left join UserPostStats ups on u.Id = ups.OwnerUserId
  left join RecursiveUserBadges db on u.Id = db.UserId and db.BadgeRank <= 5
  left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
  left join PostCloseReasons pc on p.Id = pc.PostId
  left join DuplicateLinks dup on p.Id = dup.PostId
  left join RankedPosts rp on rp.OwnerUserId = u.Id and rp.UserPostRank = 1
 where u.Reputation > 1000
 group by u.Id, u.DisplayName, ua.TotalPosts, ua.TotalComments, ua.UpVotesReceived, ua.DownVotesReceived, ua.FirstPostDate, ua.LastActivityDate, 
          ups.TotalAnswers, ups.AcceptedAnswersCount, ups.AvgScore, ups.MaxScore, ups.DistinctTagsCount,
          pc.CloseReasonName, pc.CloseDate, dup.PostTitle, dup.RelatedPostTitle, rp.UserPostRank, u.WebsiteUrl
 having count(distinct db.BadgeName) >= 1
 order by ua.UpVotesReceived desc nulls last, ua.TotalPosts desc nulls last
 limit 100;