-- {"query": "590.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1452} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        rtc.TotalAnswers + coalesce(p2.AnswerCount, 0),
        rtc.TotalViews + coalesce(p2.ViewCount, 0)
    from Tags t2
    join Posts p2 on p2.Id = t2.ExcerptPostId and p2.PostTypeId = 1
    join RecursiveTagCounts rtc on rtc.TagId <> t2.Id
    where rtc.TotalAnswers < 1000
),
UserBadgeRankings as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by u.Id order by b.Class) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, b.Class
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwner,
        (select count(*) from Comments c where c.PostId = a.Id and c.Score > 0) as PositiveComments,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswersWithVotes as (
    select
        qas.QuestionId,
        qas.Title,
        qas.AnswerId,
        qas.AnswerScore,
        qas.AnswerOwner,
        qas.PositiveComments,
        v.UpVotes,
        v.DownVotes,
        case when v.UpVotes + v.DownVotes = 0 then null else (v.UpVotes::float / (v.UpVotes + v.DownVotes)) end as UpvoteRatio
    from QuestionAnswerStats qas
    left join (
        select
            a.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes a
        join VoteTypes vt on vt.Id = a.VoteTypeId
        group by a.PostId
    ) v on v.PostId = qas.AnswerId
    where qas.AnswerRank <= 3
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsAsked,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersGiven,
        sum(p.Score) as TotalPostScore,
        max(p.CreationDate) as LastPostDate,
        count(distinct c.Id) as CommentsMade,
        sum(coalesce(vb.BadgeCount,0)) as TotalBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select UserId, count(*) as BadgeCount
        from Badges
        group by UserId
    ) vb on vb.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pt1.Title as PostTitle,
        pt2.Title as RelatedPostTitle,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join Posts pt1 on pt1.Id = pl.PostId
    join Posts pt2 on pt2.Id = pl.RelatedPostId
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
QuestionsWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.ClosedDate,
        pht.Name as CloseReason,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 6) as CloseVotesCount
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes pht on pht.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1
)
select
    uas.UserId,
    uas.DisplayName,
    uas.TotalPosts,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.TotalPostScore,
    uas.CommentsMade,
    uas.TotalBadges,
    tawc.AnswerId,
    tawc.AnswerScore,
    tawc.UpVotes,
    tawc.DownVotes,
    tawc.UpvoteRatio,
    dl.PostId as DuplicatePostId,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.PostTitle as DuplicatePostTitle,
    dl.RelatedPostTitle as OriginalPostTitle,
    dl.CreationDate as DuplicateLinkDate,
    dl.LinkTypeName,
    qwi.Id as ClosedQuestionId,
    qwi.Title as ClosedQuestionTitle,
    qwi.ClosedDate,
    qwi.CloseReason,
    qwi.CloseVotesCount,
    rtc.TagName,
    rtc.Count as TagCount,
    rtc.TotalAnswers,
    rtc.TotalViews
from UserActivitySummary uas
left join TopAnswersWithVotes tawc on tawc.AnswerOwner = uas.UserId
left join DuplicateLinks dl on dl.PostId = tawc.AnswerId
left join QuestionsWithCloseInfo qwi on qwi.Id = tawc.QuestionId
left join RecursiveTagCounts rtc on rtc.TagName = any(string_to_array(coalesce((select Tags from Posts where Id = tawc.QuestionId), ''), '><'))
where uas.TotalPosts > 50
and (tawc.UpvoteRatio is null or tawc.UpvoteRatio > 0.7)
and (qwi.ClosedDate is null or qwi.ClosedDate > current_timestamp - interval '1 year')
order by uas.TotalPostScore desc, tawc.AnswerScore desc
limit 100;