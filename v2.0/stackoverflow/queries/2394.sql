with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        0 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = false

    union all

    select
        t.Id,
        t.TagName,
        r.Level + 1,
        (r.Path || array[t.Id]) -- ensure concatenation of two arrays
    from Tags t
    join RecursiveTagHierarchy r on r.Id <> t.Id
    where not t.Id = any(r.Path) and t.IsModeratorOnly = false
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        max(b.Date) as LastBadgeDate,
        sum(case when b.TagBased = true then 1 else 0 end) as TagBasedBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        u.DisplayName as OwnerName,
        q.Score as QuestionScore,
        q.ViewCount,
        q.CreationDate as QuestionCreation,
        ans.Id as AnswerId,
        ans.OwnerUserId as AnswerOwnerId,
        auser.DisplayName as AnswerOwnerName,
        ans.Score as AnswerScore,
        ans.CreationDate as AnswerCreation,
        row_number() over (partition by q.Id order by ans.Score desc, ans.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts ans on ans.ParentId = q.Id and ans.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    left join Users auser on auser.Id = ans.OwnerUserId
    where q.PostTypeId = 1
      and q.Score > 10
      and q.ViewCount > 1000
),
FilteredAnswers as (
    select * from TopQuestionsWithAnswers
    where AnswerRank <= 3
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
UserActivityRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersCount,
        count(distinct ph.Id) as TotalEdits,
        rank() over (order by count(distinct p.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName
),
LatestCommentsPerPost as (
    select
        c.PostId,
        c.Id as CommentId,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        coalesce(u.DisplayName, c.UserDisplayName) as CommenterName
    from (
        select *,
               row_number() over (partition by PostId order by CreationDate desc) as rn
        from Comments
    ) c
    left join Users u on u.Id = c.UserId
    where c.rn = 1
),
PostLinksWithTitles as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        pt.Title as PostTitle,
        rpt.Title as RelatedPostTitle
    from PostLinks pl
    join Posts pt on pt.Id = pl.PostId
    join Posts rpt on rpt.Id = pl.RelatedPostId
),
CombinedQuestions as (
    select
        q.Id,
        q.Title,
        q.Tags,
        string_agg(distinct t.TagName, ',' order by t.TagName) as TagList,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        coalesce(usr.DisplayName, q.OwnerDisplayName) as OwnerName,
        uas.TotalPosts,
        uas.ActivityRank,
        coalesce(close.CloseReasonName, 'Open') as CloseStatus
    from Posts q
    left join lateral (
        select unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><')) as TagName
    ) foo on true
    left join Tags t on t.TagName = foo.TagName
    left join Users usr on usr.Id = q.OwnerUserId
    left join UserActivityRanks uas on uas.UserId = q.OwnerUserId
    left join PostCloseReasons close on close.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.CreationDate, q.Score, q.ViewCount, usr.DisplayName, q.OwnerDisplayName, uas.TotalPosts, uas.ActivityRank, close.CloseReasonName
)
select
    cq.Id as QuestionId,
    cq.Title,
    left(cq.TagList, 100) as TopTagsPreview,
    cq.CreationDate,
    cq.Score,
    cq.ViewCount,
    cq.OwnerName,
    cq.TotalPosts,
    cq.ActivityRank,
    cq.CloseStatus,
    coalesce(ub.GoldBadges, 0) as UserGoldBadges,
    coalesce(ub.SilverBadges, 0) as UserSilverBadges,
    coalesce(ub.BronzeBadges, 0) as UserBronzeBadges,
    (select count(*) from Posts a where a.ParentId = cq.Id) as TotalAnswers,
    (select avg(coalesce(ans.Score,0)) from Posts ans where ans.ParentId = cq.Id) as AvgAnswerScore,
    (select count(*) from Votes v where v.PostId = cq.Id and v.VoteTypeId = 2) as UpVotesQuestion,
    (select count(*) from Votes v where v.PostId in (select ans.Id from Posts ans where ans.ParentId = cq.Id) and v.VoteTypeId = 2) as UpVotesAnswers,
    (select max(ph.CreationDate) from PostHistory ph where ph.PostId = cq.Id) as LastPostHistoryEdit,
    (select lcp.CommentText from LatestCommentsPerPost lcp where lcp.PostId = cq.Id limit 1) as LatestCommentText,
    array_agg(distinct pl.RelatedPostTitle order by pl.RelatedPostTitle) filter (where pl.LinkTypeId = 3) as DuplicatePostTitles
from CombinedQuestions cq
left join UserBadgeStats ub on ub.UserId = (select Id from Users where DisplayName = cq.OwnerName limit 1)
left join PostLinksWithTitles pl on pl.PostId = cq.Id
group by
    cq.Id, cq.Title, cq.TagList, cq.CreationDate, cq.Score, cq.ViewCount, cq.OwnerName,
    cq.TotalPosts, cq.ActivityRank, cq.CloseStatus,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
order by cq.Score desc nulls last, cq.ViewCount desc nulls last
limit 50;