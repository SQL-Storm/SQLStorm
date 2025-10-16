-- {"query": "155.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1589} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id = r.Id + 1 and t2.IsModeratorOnly = 0
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.CreationDate) as CreationRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.CreationDate as QuestionCreationDate,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as OwnerDisplayName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    left join UserBadgeCounts ub on ub.UserId = q.OwnerUserId
    where q.PostTypeId = 1
      and q.Score > 10
      and q.ViewCount > 1000
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id) as AnswerCount,
        count(distinct c.Id) over (partition by u.Id) as CommentCount,
        row_number() over (order by u.Reputation desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
),
ComplexFilteredPosts as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorDisplayName,
        ph.Comment as CloseReasonComment,
        case
            when ph.PostHistoryTypeId = 10 then 'Closed'
            when ph.PostHistoryTypeId = 11 then 'Reopened'
            else 'Other'
        end as PostStatus
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate = (
        select max(ph2.CreationDate)
        from PostHistory ph2
        where ph2.PostId = p.Id
    )
    where p.PostTypeId = 1
      and (p.Score > 5 or p.ViewCount > 500)
),
FinalResult as (
    select distinct
        q.QuestionId,
        q.Title,
        q.Tags,
        q.QuestionScore,
        q.QuestionViews,
        q.QuestionCreationDate,
        q.AnswerId,
        q.AnswerScore,
        q.AnswerCreationDate,
        q.OwnerDisplayName,
        q.GoldBadges,
        q.SilverBadges,
        q.BronzeBadges,
        q.TotalBadges,
        cr.CloseReasonName,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.UserRank,
        p.PostStatus,
        p.CloseReasonComment,
        r.Level as TagHierarchyLevel,
        r.Path as TagHierarchyPath
    from TopQuestionsWithAnswers q
    left join CloseReasonCounts cr on cr.CloseReasonId = (
        select ph.Comment
        from PostHistory ph
        where ph.PostId = q.QuestionId and ph.PostHistoryTypeId = 10
        order by ph.CreationDate desc limit 1
    )
    left join UserActivityWindow ua on ua.Id = (
        select OwnerUserId from Posts where Id = q.QuestionId
    )
    left join ComplexFilteredPosts p on p.Id = q.QuestionId
    left join RecursiveTagHierarchy r on position(r.TagName in coalesce(q.Tags, '')) > 0
    where ua.UserRank <= 100
)
select
    fr.QuestionId,
    fr.Title,
    fr.Tags,
    fr.QuestionScore,
    fr.QuestionViews,
    fr.QuestionCreationDate,
    fr.AnswerId,
    fr.AnswerScore,
    fr.AnswerCreationDate,
    coalesce(fr.OwnerDisplayName, 'Anonymous') as OwnerDisplayName,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.TotalBadges,
    coalesce(fr.CloseReasonName, 'Open') as CloseReasonName,
    fr.QuestionCount,
    fr.AnswerCount,
    fr.CommentCount,
    fr.UserRank,
    fr.PostStatus,
    fr.CloseReasonComment,
    fr.TagHierarchyLevel,
    fr.TagHierarchyPath,
    length(fr.Title) as TitleLength,
    case when fr.QuestionScore > 50 then 'HighScore' else 'NormalScore' end as ScoreCategory,
    substring(fr.Tags from 2 for 100) as TagsSnippet,
    (fr.QuestionScore * 1.0 / nullif(fr.QuestionViews,0)) as ScoreToViewRatio
from FinalResult fr
where fr.QuestionScore > 10 or fr.AnswerScore > 5
order by fr.UserRank, fr.QuestionScore desc, fr.AnswerScore desc
limit 100;