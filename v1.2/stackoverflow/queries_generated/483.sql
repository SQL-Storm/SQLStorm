-- {"query": "483.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1791} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        child.Id,
        child.TagName,
        child.Count,
        child.IsModeratorOnly,
        child.IsRequired,
        p.Level + 1,
        p.Path || child.TagName
    from Tags child
    join RecursiveTagHierarchy p on child.IsRequired = 1 and child.Id <> p.Id and not child.TagName = any(p.Path)
    where p.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserPostStats as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate,
        avg(p.ViewCount) filter (where p.PostTypeId = 1) as AvgQuestionViews,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAcceptedAnswer
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
PostAnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
TopAnswersWithComments as (
    select
        a.AnswerId,
        a.QuestionId,
        a.Score,
        a.AnswerRank,
        coalesce(c.CommentCount,0) as CommentCount,
        coalesce(c.MaxCommentScore,0) as MaxCommentScore
    from PostAnswerRanks a
    left join (
        select
            PostId,
            count(*) as CommentCount,
            max(Score) as MaxCommentScore
        from Comments
        group by PostId
    ) c on c.PostId = a.AnswerId
    where a.AnswerRank <= 3
),
UserActivityWindows as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers,
        sum(p.Score) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pl.LinkTypeId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
ComplexFilteredPosts as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        p.LastActivityDate,
        p.PostTypeId,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered'
            else 'Open'
        end as PostStatus,
        -- Extract first tag or null if no tags
        split_part(substring(p.Tags from 2 for length(p.Tags)-2), '><', 1) as FirstTag,
        -- Calculate weighted score with logarithmic scaling and null-safe
        coalesce(p.Score,0) * ln(coalesce(p.ViewCount,1) + 1) as WeightedScore
    from Posts p
    where p.PostTypeId in (1,2)
),
UserTopTags as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null
    group by p.OwnerUserId, Tag
),
UserDominantTag as (
    select distinct on (UserId)
        UserId,
        Tag,
        TagCount
    from UserTopTags
    order by UserId, TagCount desc
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(ubc_badge.GoldCount,0) as GoldBadges,
    coalesce(ubc_badge.SilverCount,0) as SilverBadges,
    coalesce(ubc_badge.BronzeCount,0) as BronzeBadges,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalPostScore,
    ups.AvgQuestionViews,
    ups.QuestionsWithAcceptedAnswer,
    dt.Tag as DominantTag,
    dt.TagCount as DominantTagCount,
    pc.CloseReasonName,
    pc.CloseDate,
    cap.AnswerId as TopAnswerId,
    cap.Score as TopAnswerScore,
    cap.CommentCount as TopAnswerCommentCount,
    cap.MaxCommentScore as TopAnswerMaxCommentScore,
    cf.PostStatus,
    cf.WeightedScore,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateRelatedPostTitle,
    ua.CumulativeQuestions,
    ua.CumulativeAnswers,
    ua.CumulativeScore
from Users u
left join UserBadgeCounts ubc on ubc.UserId = u.Id
left join (
    select
        UserId,
        max(case when Class = 1 then BadgeCount else 0 end) as GoldCount,
        max(case when Class = 2 then BadgeCount else 0 end) as SilverCount,
        max(case when Class = 3 then BadgeCount else 0 end) as BronzeCount
    from UserBadgeCounts
    group by UserId
) ubc_badge on ubc_badge.UserId = u.Id
left join UserPostStats ups on ups.UserId = u.Id
left join UserDominantTag dt on dt.UserId = u.Id
left join PostCloseReasons pc on pc.PostId in (
    select Id from Posts where OwnerUserId = u.Id limit 1
)
left join TopAnswersWithComments cap on cap.QuestionId in (
    select Id from Posts where OwnerUserId = u.Id and PostTypeId = 1 limit 1
)
left join ComplexFilteredPosts cf on cf.OwnerUserId = u.Id
left join DuplicateLinks dup on dup.PostId in (
    select Id from Posts where OwnerUserId = u.Id limit 1
)
left join UserActivityWindows ua on ua.UserId = u.Id and ua.CreationDate = (
    select max(CreationDate) from UserActivityWindows where UserId = u.Id
)
where u.Reputation > 1000
order by u.Reputation desc
limit 100;