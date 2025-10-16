-- {"query": "704.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1744} 
with RecursiveTagHierarchy as (
    select 
        t.Id, 
        t.TagName, 
        t.Count, 
        0 as Level,
        cast(t.TagName as varchar(1000)) as FullPath
    from Tags t
    where t.Id = (select min(Id) from Tags)
    union all
    select 
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.FullPath || ' > ' || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id + 1 and t.Count <= r.Count * 1.5
    where r.Level < 5
),
UserBadgeStats as (
    select 
        u.Id as UserId, 
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityCTE as (
    select 
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.Comment as CloseReasonId,
        row_number() over (partition by p.Id order by ph.CreationDate desc) as rn
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (10,11,12,13,14,15)
),
LatestPostActivity as (
    select * from PostActivityCTE where rn = 1
),
UserPostStats as (
    select 
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews,
        count(distinct c.Id) as CommentsMade,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesGiven,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesGiven
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id
),
TopQuestionsWithAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.ClosedDate is null
    and q.Score > 5
),
TopAnswersRanked as (
    select * from TopQuestionsWithAnswers where AnswerRank <= 3
),
DuplicatedPosts as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name = 'Duplicate'
),
CloseReasonSummary as (
    select 
        crt.Name as CloseReason,
        count(distinct ph.PostId) as ClosedPostsCount,
        avg(date_part('epoch', coalesce(ph.CreationDate, current_timestamp) - p.CreationDate)/3600) as AvgHoursToClose
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    group by crt.Name
),
UserActivityRanking as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ups.QuestionsAsked,0) as QuestionsAsked,
        coalesce(ups.AnswersGiven,0) as AnswersGiven,
        coalesce(ups.CommentsMade,0) as CommentsMade,
        coalesce(ups.UpVotesGiven,0) as UpVotesGiven,
        coalesce(ups.DownVotesGiven,0) as DownVotesGiven,
        rank() over (order by u.Reputation desc, coalesce(ups.AnswersGiven,0) desc) as UserRank
    from Users u
    left join UserPostStats ups on ups.UserId = u.Id
)
select 
    uar.UserRank,
    uar.DisplayName as User,
    uar.Reputation,
    uar.QuestionsAsked,
    uar.AnswersGiven,
    uar.CommentsMade,
    uar.UpVotesGiven,
    uar.DownVotesGiven,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    lpa.PostTypeId,
    lpa.PostId,
    lpa.HistoryDate as LastActivityOnPost,
    crs.CloseReason,
    crs.ClosedPostsCount,
    crs.AvgHoursToClose,
    dt.PostTitle as DuplicatePostTitle,
    dt.RelatedPostTitle as DuplicateRelatedTitle,
    dt.LinkTypeName,
    th.FullPath as TagHierarchyPath,
    thar.Level as TagLevel,
    topa.QuestionId,
    topa.Title as QuestionTitle,
    topa.AnswerId,
    topa.AnswerScore,
    topa.AnswerOwnerName,
    case 
        when strpos(coalesce(topa.Title,''), 'SQL') > 0 then 'Contains SQL'
        else 'Other Topic'
    end as QuestionTopicCategory,
    length(coalesce(topa.Title,'')) as QuestionTitleLength,
    (select count(*) from Comments c where c.PostId = topa.QuestionId and c.Score > 0) as PositiveCommentsOnQuestion
from UserActivityRanking uar
left join UserBadgeStats ubs on ubs.UserId = uar.Id
left join LatestPostActivity lpa on lpa.OwnerUserId = uar.Id
left join CloseReasonSummary crs on crs.CloseReason = (
    select crt.Name from CloseReasonTypes crt 
    join PostHistory ph on ph.Comment = cast(crt.Id as varchar) 
    where ph.PostId = lpa.PostId and ph.PostHistoryTypeId = 10
    order by ph.CreationDate desc limit 1
)
left join DuplicatedPosts dt on dt.PostId = lpa.PostId
left join RecursiveTagHierarchy th on th.TagName = any(string_to_array(coalesce(lpa.Tags,''), '><'))
left join RecursiveTagHierarchy thar on thar.Id = th.Id
left join TopAnswersRanked topa on topa.AnswerOwnerUserId = uar.Id
where uar.UserRank <= 100
order by uar.UserRank, lpa.HistoryDate desc
limit 50;