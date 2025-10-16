-- {"query": "174.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1690} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> all(r.Path)
    where t.IsRequired = 1 and t.Count < r.Count
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        row_number() over (partition by u.Location order by u.Reputation desc) as RankInLocation,
        avg(u.Reputation) over (partition by u.Location) as AvgReputationInLocation,
        count(*) over (partition by u.Location) as UsersInLocation
    from Users u
    where u.Location is not null
),
PostScoreStats as (
    select
        p.OwnerUserId,
        count(*) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        sum(p.ViewCount) as TotalViews,
        sum(p.FavoriteCount) as TotalFavorites
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
      and q.Score > 10
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserDisplayName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as PostsCount,
        count(distinct c.Id) as CommentsCount,
        count(distinct v.Id) as VotesCount,
        count(distinct b.Id) as BadgesCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotesGiven,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotesGiven
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
ComplexStringAnalysis as (
    select
        p.Id,
        p.Title,
        p.Tags,
        length(p.Body) as BodyLength,
        length(coalesce(p.Tags, '')) as TagsLength,
        strpos(lower(p.Body), 'sql') as SqlPositionInBody,
        strpos(lower(p.Title), 'sql') as SqlPositionInTitle,
        case
            when p.Tags is null then 'No Tags'
            when p.Tags like '%<sql>%' then 'Has SQL Tag'
            else 'Other Tags'
        end as TagCategory
    from Posts p
    where p.PostTypeId = 1
),
FinalResult as (
    select
        u.Id as UserId,
        u.DisplayName,
        urw.RankInLocation,
        urw.AvgReputationInLocation,
        urw.UsersInLocation,
        coalesce(pss.TotalPosts,0) as TotalPosts,
        coalesce(pss.QuestionCount,0) as QuestionCount,
        coalesce(pss.AnswerCount,0) as AnswerCount,
        coalesce(pss.AvgScore,0) as AvgPostScore,
        coalesce(ubc.BadgeCount,0) as GoldBadges,
        coalesce(ubc2.BadgeCount,0) as SilverBadges,
        coalesce(ubc3.BadgeCount,0) as BronzeBadges,
        uas.PostsCount,
        uas.CommentsCount,
        uas.VotesCount,
        uas.BadgesCount,
        uas.UpVotesGiven,
        uas.DownVotesGiven,
        dq.PostId as DuplicateQuestionId,
        dq.RelatedPostId as DuplicateOfQuestionId,
        dq.PostTitle as DuplicateQuestionTitle,
        dq.RelatedPostTitle as DuplicateOfQuestionTitle,
        csa.Title as SampleQuestionTitle,
        csa.TagCategory,
        csa.BodyLength,
        csa.SqlPositionInBody,
        csa.SqlPositionInTitle
    from Users u
    left join UserReputationWindow urw on urw.Id = u.Id
    left join PostScoreStats pss on pss.OwnerUserId = u.Id
    left join UserBadgeCounts ubc on ubc.UserId = u.Id and ubc.Class = 1
    left join UserBadgeCounts ubc2 on ubc2.UserId = u.Id and ubc2.Class = 2
    left join UserBadgeCounts ubc3 on ubc3.UserId = u.Id and ubc3.Class = 3
    left join UserActivitySummary uas on uas.UserId = u.Id
    left join DuplicateLinks dq on dq.PostId = (
        select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by p.Score desc limit 1
    )
    left join ComplexStringAnalysis csa on csa.Id = (
        select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by p.CreationDate desc limit 1
    )
    where u.Reputation > 1000
)
select *
from FinalResult
order by AvgPostScore desc, TotalPosts desc
limit 100;