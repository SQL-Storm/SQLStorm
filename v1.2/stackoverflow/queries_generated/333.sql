-- {"query": "333.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1493} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        array[t.TagName] as AncestorPath
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.AncestorPath || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id + 1
    where r.Level < 3
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.Score) as MaxPostScore,
        avg(p.Score) as AvgPostScore,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        row_number() over (order by coalesce(sum(p.Score),0) desc) as ScoreRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Tags,
        c.CommentCount,
        coalesce(c.CommentsText, '') as CommentsText,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as PostRank
    from Posts p
    left join (
        select
            PostId,
            count(*) as CommentCount,
            string_agg(Text, ' ||| ' order by CreationDate desc) as CommentsText
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwner,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AnswerUpVotes,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3) as AnswerDownVotes,
        case when a.Score >= 10 then 'High' when a.Score between 5 and 9 then 'Medium' else 'Low' end as AnswerQuality
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(p.Score) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as ScoreLast30Days
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where p.CreationDate > current_date - interval '90 days'
),
CloseReasonSummary as (
    select
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1 and p.ClosedDate is not null
)
select
    u.DisplayName,
    u.Reputation,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalPostScore,
    ups.GoldBadges,
    ups.SilverBadges,
    ups.BronzeBadges,
    coalesce(tp.PostRank, 0) as TopPostRank,
    coalesce(tp.Title, '') as TopPostTitle,
    coalesce(tp.Score, 0) as TopPostScore,
    coalesce(tp.CommentCount, 0) as TopPostCommentCount,
    coalesce(aa.AnswerQuality, 'None') as AcceptedAnswerQuality,
    coalesce(dl.DuplicateCount, 0) as DuplicateLinksCount,
    coalesce(ua.PostsLast30Days, 0) as PostsInLast30Days,
    coalesce(ua.ScoreLast30Days, 0) as ScoreInLast30Days,
    cr.CloseReasonName,
    cr.CloseDate
from Users u
left join UserPostStats ups on ups.UserId = u.Id
left join TopPostsWithComments tp on tp.OwnerUserId = u.Id and tp.PostRank = 1
left join (
    select
        QuestionOwner,
        count(*) as DuplicateCount
    from DuplicateLinks
    group by QuestionOwner
) dl on dl.QuestionOwner = u.Id
left join AcceptedAnswerStats aa on aa.QuestionOwner = u.Id
left join UserActivityWindow ua on ua.UserId = u.Id
left join CloseReasonSummary cr on cr.PostId = tp.Id
where u.Reputation > 1000
order by ups.TotalPostScore desc, ups.QuestionCount desc
limit 100;