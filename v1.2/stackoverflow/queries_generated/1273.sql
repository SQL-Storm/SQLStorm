-- {"query": "1273.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1189} 
with RecursiveTagCounts as (
    select t.Id, t.TagName, t.Count, p.Id as PostId, p.Score,
           row_number() over (partition by t.Id order by p.Score desc nulls last, p.CreationDate) as RankByScore
      from Tags t
      left join Posts p
        on p.Tags like concat('%<', t.TagName, '>%')
    union all 
    select rtc.Id, rtc.TagName, rtc.Count, p2.Id, p2.Score,
           row_number() over (partition by rtc.Id order by p2.Score desc nulls last, p2.CreationDate)
      from RecursiveTagCounts rtc
      join Posts p2 on p2.ParentId = rtc.PostId and p2.PostTypeId = 2 -- answers
),
UserBadgeCounts as (
    select u.Id as UserId, 
           u.DisplayName,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
           count(b.Id) as TotalBadges
      from Users u
      left join Badges b 
        on b.UserId = u.Id
      group by u.Id, u.DisplayName
),
UserActivity AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.CreationDate,
           (select count(p.Id) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as QuestionCount,
           (select count(p.Id) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswerCount,
           (select count(c.Id) from Comments c where c.UserId = u.Id) as CommentCount,
           (select count(v.Id) from Votes v where v.UserId = u.Id and v.VoteTypeId = 3) as DownVoteCount,
           (select count(v.Id) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2) as UpVoteCount,
           case 
             when u.LastAccessDate is null or u.CreationDate is null then null
             else extract(day from u.LastAccessDate - u.CreationDate)
           end as DaysActive
      FROM Users u
),
TopTagQuestions AS (
    select t.Id as TagId, t.TagName, count(p.Id) as QuestionCount,
           avg(coalesce(p.Score,0)) as AvgScore, 
           count(distinct p.OwnerUserId) as DistinctAskers,
           max(p.ViewCount) as MaxViewCount,
           string_agg(distinct u.DisplayName, ', ' order by u.Reputation desc) filter (WHERE u.DisplayName IS NOT NULL) as ActiveUsers
      from Tags t
      inner join Posts p on p.Tags like concat('%<', t.TagName, '>%')
      left join Users u on u.Id = p.OwnerUserId
      where p.PostTypeId = 1
      group by t.Id, t.TagName
      having count(p.Id) > 5
),
FilteredPostsWithVotes AS (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount,
           count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
           count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
           rank() over (partition by p.PostTypeId order by p.Score desc nulls last, p.CreationDate) as RankByScore
      from Posts p
      left join Votes v on v.PostId = p.Id
      where p.CreationDate >= '2022-01-01' and p.CreationDate < '2023-01-01'
      group by p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
)
select ua.DisplayName,
       ua.Reputation,
       ua.QuestionCount,
       ua.AnswerCount,
       ua.CommentCount,
       ua.UpVoteCount,
       ua.DownVoteCount,
       ub.GoldBadges,
       ub.SilverBadges,
       ub.BronzeBadges,
       ua.DaysActive,
       ttq.TagName,
       ttq.QuestionCount as TagQuestionCount,
       ttq.AvgScore as TagAvgScore,
       ttq.DistinctAskers,
       ttq.MaxViewCount,
       ttq.ActiveUsers,
       fp.Id as TopPostId,
       fp.Score as TopPostScore,
       fp.ViewCount as TopPostViews,
       fp.UpVotes as TopPostUpVotes,
       fp.DownVotes as TopPostDownVotes
  from UserActivity ua
  left join UserBadgeCounts ub on ub.UserId = ua.UserId
  left join TopTagQuestions ttq on ttq.QuestionCount = (
        select max(QuestionCount) from TopTagQuestions where TagName in (
            select unnest(string_to_array(coalesce((select Tags from Posts where Id = fp.Id), ''), '><'))
        )
  )
  left join LATERAL (
    select * 
      from FilteredPostsWithVotes 
     where OwnerUserId = ua.UserId and RankByScore = 1
     limit 1
    ) fp on true
  where ua.Reputation > 10000
    and ua.QuestionCount > 10
  order by ua.Reputation desc
  limit 25;