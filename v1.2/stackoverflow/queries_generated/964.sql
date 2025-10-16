-- {"query": "964.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1291} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(t.Count, 0) as TotalCount,
        1 as Level
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        rtc.TotalCount + coalesce(t2.Count, 0),
        rtc.Level + 1
    from Tags t2
    join RecursiveTagCounts rtc on t2.IsModeratorOnly = 0 and t2.Id > rtc.TagId
    where rtc.Level < 3
),
UserStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(b.BadgeCounts, 0) as BadgeCount,
        coalesce(ans.AnswerCount, 0) as TotalAnswers,
        coalesce(q.QuestionsAsked, 0) as TotalQuestions,
        coalesce(fav.FavPosts, 0) as FavoritePosts
    from Users u
    left join (
        select
            UserId,
            count(*) as BadgeCounts
        from Badges
        group by UserId
    ) b on u.Id = b.UserId
    left join (
        select
            OwnerUserId,
            count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) ans on u.Id = ans.OwnerUserId
    left join (
        select
            OwnerUserId,
            count(*) as QuestionsAsked
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) q on u.Id = q.OwnerUserId
    left join (
        select
            UserId,
            count(*) as FavPosts
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id and vt.Name = 'Favorite'
        group by UserId
    ) fav on u.Id = fav.UserId
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(cmt.CommentCount, 0) as CommentCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as rn
    from Posts p
    left join (
        select
            PostId,
            count(*) as CommentCount
        from Comments
        group by PostId
    ) cmt on p.Id = cmt.PostId
    where p.PostTypeId = 1
),
ClosedPostStats as (
    select
        p.Id,
        p.Title,
        p.ClosedDate,
        cht.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes cht on cht.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where p.ClosedDate is not null
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as AnswerCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownvotes
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
    group by a.ParentId
),
UserBadgeWindow as (
    select
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        rank() over (partition by b.UserId order by b.Date) as BadgeRank
    from Badges b
),
RecursiveDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        1 as DupLevel
    from PostLinks pl
    where pl.LinkTypeId = 3

    union all

    select
        r.PostId,
        pl.RelatedPostId,
        r.DupLevel + 1
    from PostLinks pl
    join RecursiveDuplicates r on pl.PostId = r.RelatedPostId
    where pl.LinkTypeId = 3 and r.DupLevel < 5
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    us.BadgeCount,
    us.TotalAnswers,
    us.TotalQuestions,
    us.FavoritePosts,
    tpc.Title as TopQuestionTitle,
    tpc.Score as TopQuestionScore,
    tpc.ViewCount as TopQuestionViews,
    tpc.CommentCount as TopQuestionComments,
    aps.AnswerCount,
    aps.TotalUpvotes,
    aps.TotalDownvotes,
    cps.Title as ClosedQuestionTitle,
    cps.CloseReason,
    cps.ClosedByUserName,
    rtc.Level as TagRecursionLevel,
    rtc.TagName,
    rtc.TotalCount as TagTotalCount,
    ubw.Name as RecentBadge,
    ubw.Class as RecentBadgeClass
from Users u
left join UserStats us on u.Id = us.Id
left join TopPostsWithComments tpc on tpc.OwnerUserId = u.Id and tpc.rn = 1
left join AnswerStats aps on aps.QuestionId = tpc.Id
left join ClosedPostStats cps on cps.ClosedByUserId = u.Id
left join RecursiveTagCounts rtc on rtc.Level = 2
left join UserBadgeWindow ubw on ubw.UserId = u.Id and ubw.BadgeRank = 1
where u.Reputation > (
    select avg(Reputation) from Users
)
and (
    tpc.Score > 5 or aps.AnswerCount > 3
)
and (
    cps.ClosedDate is null or cps.CloseReason not in ('Exact Duplicate', 'Duplicate')
)
order by u.Reputation desc, tpc.Score desc
limit 100;