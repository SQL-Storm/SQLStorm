-- {"query": "2086.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1848} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over(partition by u.Id order by b.Date desc) rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Name is not null
),
TopBadgesPerUser as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where rn <= 3
),
PostVoteStats as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotes,
        coalesce(sum(case when v.VoteTypeId = 5 then 1 else 0 end),0) as Favorites,
        count(v.Id) as TotalVotes
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id, p.PostTypeId
),
QuestionAnswerLinks as (
    select 
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        rank() over(partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
LatestCommentsPerPost as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Text as CommentText,
        c.CreationDate
    from Comments c
    order by c.PostId, c.CreationDate desc
),
ClosedQuestions as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonId,
        max(ph.CreationDate) as CloseDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
ComplexQuestions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.FavoriteCount,
        pv.UpVotes,
        pv.DownVotes,
        pv.Favorites,
        coalesce(cl.CloseReasonId::int, 0) as CloseReasonId,
        cl.CloseDate,
        lc.CommentText as LastCommentText,
        case 
            when p.Tags is null then '{}'
            else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')
        end as TagArray
    from Posts p
    left join PostVoteStats pv on p.Id = pv.PostId
    left join ClosedQuestions cl on p.Id = cl.PostId
    left join LatestCommentsPerPost lc on p.Id = lc.PostId
    where p.PostTypeId = 1
),
UserActivitySummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        count(distinct b.Id) as BadgeCount,
        max(u.Reputation) as MaxReputation,
        min(u.CreationDate) as FirstSeen,
        max(u.LastAccessDate) as LastActive,
        bool_or(b.Class = 1) as HasGoldBadge
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserQuestionAnswerStats as (
    select
        u.Id as UserId,
        count(distinct q.Id) as AskedQuestions,
        count(distinct a.Id) as GivenAnswers,
        coalesce(avg(q.Score),0) as AvgQuestionScore,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        coalesce(max(q.Score),0) as MaxQuestionScore,
        coalesce(max(a.Score),0) as MaxAnswerScore,
        count(distinct ac.Id) as AnswerCommentsCount
    from Users u
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Comments ac on ac.PostId = a.Id
    group by u.Id
),
UserWithBadgesAndActivity as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.TotalPosts,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.BadgeCount,
        ua.MaxReputation,
        ua.FirstSeen,
        ua.LastActive,
        ua.HasGoldBadge,
        uqa.AskedQuestions,
        uqa.GivenAnswers,
        uqa.AvgQuestionScore,
        uqa.AvgAnswerScore,
        uqa.MaxQuestionScore,
        uqa.MaxAnswerScore,
        uqa.AnswerCommentsCount,
        tb.BadgeName,
        tb.Class as BadgeClass
    from UserActivitySummary ua
    left join UserQuestionAnswerStats uqa on ua.UserId = uqa.UserId
    left join TopBadgesPerUser tb on ua.UserId = tb.UserId
),
AllUserPairs as (
    select 
        u1.UserId as User1Id, u1.DisplayName as User1Name,
        u2.UserId as User2Id, u2.DisplayName as User2Name,
        u1.MaxReputation as User1Rep,
        u2.MaxReputation as User2Rep,
        u1.BadgeCount as User1Badges,
        u2.BadgeCount as User2Badges
    from UserWithBadgesAndActivity u1
    join UserWithBadgesAndActivity u2 on u1.UserId < u2.UserId
    where u1.HasGoldBadge = true and u2.HasGoldBadge = true
)
select distinct
    cq.QuestionId,
    cq.Title,
    cq.CreationDate,
    cq.Score,
    cq.ViewCount,
    array_to_string(cq.TagArray, ',') as Tags,
    cq.OwnerUserId,
    coalesce(u.DisplayName, 'Unknown') as OwnerDisplayName,
    cq.AnswerCount,
    cq.FavoriteCount,
    cq.UpVotes,
    cq.DownVotes,
    cq.Favorites,
    coalesce(crt.Name, 'Open') as CloseReason,
    cq.CloseDate,
    cq.LastCommentText,
    pq.AnswerId as TopAnswerId,
    pq.AnswerScore as TopAnswerScore,
    pq.AnswerCreationDate as TopAnswerCreationDate,
    u2.DisplayName as DuplicateLinkedUserName,
    u2.MaxReputation as DuplicateLinkedUserReputation,
    au.User1Name,
    au.User2Name,
    au.User1Rep,
    au.User2Rep,
    rbt.BadgeName,
    rbt.BadgeClass
from ComplexQuestions cq
left join PostLinks pl on pl.PostId = cq.QuestionId and pl.LinkTypeId = 3 -- duplicates
left join Posts dup on dup.Id = pl.RelatedPostId and dup.PostTypeId = 1
left join Users u on cq.OwnerUserId = u.Id
left join QuestionAnswerLinks pq on pq.QuestionId = cq.QuestionId and pq.AnswerRank = 1
left join Users u2 on dup.OwnerUserId = u2.Id
left join CloseReasonTypes crt on crt.Id::int = cq.CloseReasonId
left join AllUserPairs au on au.User1Id = cq.OwnerUserId or au.User2Id = cq.OwnerUserId
left join RecursiveUserBadges rbt on rbt.UserId = au.User1Id and rbt.rn = 1
where cq.Score > 5 and cq.ViewCount > 1000 and (cq.CloseDate is null or cq.CloseDate > now() - interval '1 year')
  and (array_length(cq.TagArray,1) is null or array_length(cq.TagArray,1) > 1)
order by cq.ViewCount desc, cq.Score desc
limit 50;