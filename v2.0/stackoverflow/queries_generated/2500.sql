-- {"query": "2500.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1657} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired, 1 as Level,
           cast(t.TagName as varchar(100)) as HierarchyPath
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select child.Id, child.TagName, child.Count, child.IsModeratorOnly, child.IsRequired, p.Level + 1,
           p.HierarchyPath || ' > ' || child.TagName
    from Tags child
    join PostLinks pl on pl.PostId = child.ExcerptPostId
    join RecursiveTagHierarchy p on pl.RelatedPostId = p.Id
    where child.IsModeratorOnly = 0 and child.IsRequired = 0 and p.Level < 3
),
UserPostAggregates as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as TotalUpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as TotalDownVotes,
        max(b.Date) filter (where b.Class = 1) as LastGoldBadgeDate,
        string_agg(distinct b.Name, ', ') filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadgeCount,
        count(b.Id) filter (where b.Class = 3) as BronzeBadgeCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostCommentDetails as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        coalesce(c.CommentCount,0) as CommentCount,
        coalesce(pc.MaxCommentScore,0) as MaxCommentScore,
        coalesce(pc.AvgCommentScore,0) as AvgCommentScore,
        row_number() over (partition by p.Id order by c.Score desc nulls last) as TopCommentRank,
        c.Text as TopCommentText
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select PostId,
               max(Score) as MaxCommentScore,
               avg(nullif(Score,0)) filter (where Score > 0) as AvgCommentScore,
               max(Score) filter (where Score is not null) as TopCommentScore
        from Comments
        group by PostId
    ) pc on pc.PostId = p.Id
    left join lateral (
        select Text
        from Comments c2
        where c2.PostId = p.Id
        order by c2.Score desc nulls last
        limit 1
    ) c on true
),
ClosedDuplicateQuestions as (
    select distinct p.Id as QuestionId, p.Title, p.Tags, ph.Comment as CloseReason,
           pl.RelatedPostId as DuplicateOfId,
           rq.Title as DuplicateOfTitle
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    left join Posts rq on rq.Id = pl.RelatedPostId
    where p.PostTypeId = 1 and ph.Comment is not null
),
UserAnswerStats as (
    select
        a.OwnerUserId,
        count(a.Id) as AnswersCount,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswersCount,
        max(a.CreationDate) as LastAnswerDate
    from Posts a
    left join Posts q on q.Id = a.ParentId
    where a.PostTypeId = 2 and a.OwnerUserId is not null
    group by a.OwnerUserId
),
UserRankings as (
    select
        ua.OwnerUserId,
        ua.AnswersCount,
        ua.AvgAnswerScore,
        ua.AcceptedAnswersCount,
        ua.LastAnswerDate,
        up.QuestionCount,
        up.TotalPostScore,
        row_number() over (order by ua.AcceptedAnswersCount desc nulls last, ua.AnswersCount desc nulls last, ua.AvgAnswerScore desc nulls last) as UserRank
    from UserAnswerStats ua
    left join (
        select OwnerUserId, count(*) as QuestionCount, sum(Score) as TotalPostScore
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) up on up.OwnerUserId = ua.OwnerUserId
)
select
    u.Id as UserId,
    u.DisplayName,
    ur.UserRank,
    ur.AnswersCount,
    ur.AvgAnswerScore,
    ur.AcceptedAnswersCount,
    ur.LastAnswerDate,
    upag.QuestionsCount,
    upag.TotalPostScore,
    upag.TotalUpVotes,
    upag.TotalDownVotes,
    upag.GoldBadges,
    upag.SilverBadgeCount,
    upag.BronzeBadgeCount,
    coalesce(cd.QuestionId, -1) as ClosedDuplicateQuestionId,
    cd.CloseReason,
    cd.DuplicateOfId,
    cd.DuplicateOfTitle,
    pcd.PostId as SamplePostId,
    pcd.Title as SamplePostTitle,
    pcd.Score as SamplePostScore,
    pcd.ViewCount as SamplePostViews,
    pcd.CommentCount as SamplePostCommentCount,
    pcd.MaxCommentScore as SamplePostMaxCommentScore,
    pcd.AvgCommentScore as SamplePostAvgCommentScore,
    pcd.TopCommentText as SamplePostTopCommentText,
    string_agg(distinct rth.HierarchyPath, ' | ') as TagHierarchies
from Users u
left join UserRankings ur on ur.OwnerUserId = u.Id
left join UserPostAggregates upag on upag.UserId = u.Id
left join ClosedDuplicateQuestions cd on cd.QuestionId in (
    select p.Id
    from Posts p
    where p.OwnerUserId = u.Id and p.PostTypeId = 1
    limit 1
)
left join lateral (
    select p.Id, p.Title, p.Score, p.ViewCount, p.CommentCount
    from Posts p
    where p.OwnerUserId = u.Id
    order by p.CreationDate desc nulls last
    limit 1
) pcd on true
left join lateral (
    select array_to_string(
        array(
            select r.HierarchyPath
            from RecursiveTagHierarchy r
            where r.TagName = ANY(
                string_to_array(
                    regexp_replace(pcd.Tags, '[<>]', '', 'g'), ' '
                )
            )
        ), ' | '
    ) as tagpaths
) rth on true
where u.Reputation > 1000
order by ur.UserRank nulls last, upag.TotalPostScore desc nulls last
limit 100;