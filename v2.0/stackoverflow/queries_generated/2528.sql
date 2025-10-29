-- {"query": "2528.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1367} 
with RecursiveTagCounts as (
    select 
        t.Id as TagId,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        ROW_NUMBER() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    join Posts p on p.Tags is not null and POSITION(CONCAT('<', t.TagName, '>') in p.Tags) > 0
    where p.PostTypeId = 1 -- questions only
),
TopTagPosts as (
    select 
        TagId,
        TagName,
        PostId,
        OwnerUserId,
        CreationDate,
        Score,
        AnswerCount
    from RecursiveTagCounts
    where rn <= 10
),
UserBadgeScore as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 5 else 0 end) 
         + sum(case when b.Class = 2 then 3 else 0 end) 
         + sum(case when b.Class = 3 then 1 else 0 end) as BadgeScore
    from Badges b
    group by b.UserId
),
UserPostStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(ubs.BadgeScore, 0) as BadgeScore,
        count(distinct p.Id) as TotalPosts,
        sum(p.Score) as TotalPostScore,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        count(distinct ph.Id) as TotalEdits,
        count(distinct c.Id) as TotalComments,
        max(p.LastActivityDate) as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.UserId = u.Id and ph.PostHistoryTypeId in (4,5,6,19,20)
    left join Comments c on c.UserId = u.Id
    left join UserBadgeScore ubs on ubs.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, ubs.BadgeScore
),
TopUsersPerTag as (
    select
        t.TagId,
        t.TagName,
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.BadgeScore,
        count(p.Id) as PostsInTag,
        sum(p.Score) as ScoreInTag,
        row_number() over(partition by t.TagId order by sum(p.Score) desc, count(p.Id) desc) as rn
    from TopTagPosts t
    join Posts p on p.Id = t.PostId and p.OwnerUserId is not null
    join Users ups on ups.Id = p.OwnerUserId
    group by t.TagId, t.TagName, ups.UserId, ups.DisplayName, ups.Reputation, ups.BadgeScore
),
CombinedUserActivity as (
    select 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.BadgeScore,
        u.TotalPosts,
        u.TotalPostScore,
        u.AvgPostScore,
        u.MaxPostScore,
        u.TotalEdits,
        u.TotalComments,
        u.LastActivityDate,
        t.TagName,
        t.PostsInTag,
        t.ScoreInTag,
        rank() over (partition by u.UserId order by t.ScoreInTag desc nulls last) as TagRank
    from UserPostStats u
    left join TopUsersPerTag t on t.UserId = u.UserId and t.rn = 1
),
RecentHighScorePosts as (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        dense_rank() over (order by p.Score desc) as ScoreRank,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(c.Id) as CommentCount
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join Votes v on v.PostId = p.Id
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1 -- questions only
      and p.CreationDate > CURRENT_DATE - INTERVAL '180 days'
      and p.Score > 10
    group by p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName, p.AcceptedAnswerId
),
AcceptedAnswerScores as (
    select 
        p.Id as QuestionId,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
),
FinalResult as (
    select 
        r.Id as QuestionId,
        r.Title,
        r.CreationDate,
        r.Score as QuestionScore,
        r.ViewCount,
        r.OwnerUserId,
        r.OwnerDisplayName,
        a.AcceptedAnswerScore,
        r.UpVotes,
        r.DownVotes,
        r.CommentCount,
        u.BadgeScore,
        u.TotalPosts,
        u.TotalPostScore,
        u.MaxPostScore,
        u.LastActivityDate,
        coalesce(ct.ScoreInTag, 0) as UserTopTagScore,
        coalesce(ct.TagName, 'N/A') as UserTopTag
    from RecentHighScorePosts r
    left join AcceptedAnswerScores a on a.QuestionId = r.Id
    left join CombinedUserActivity u on u.UserId = r.OwnerUserId
    left join TopUsersPerTag ct on ct.UserId = r.OwnerUserId and ct.rn = 1
    where (a.AcceptedAnswerScore is null or a.AcceptedAnswerScore < r.Score) -- questions where accepted answer scores less than question
    order by r.Score desc, UserTopTagScore desc nulls last, u.BadgeScore desc nulls last
    limit 25
)
select * from FinalResult;