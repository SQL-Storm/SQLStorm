-- {"query": "418.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1792} 
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
        cast(t.TagName as varchar(100)) as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        r.Level + 1,
        r.Path || ' > ' || child.TagName
    from Tags child
    inner join RecursiveTagHierarchy r on child.Id <> r.Id and child.IsRequired = 1 and child.Count < r.Count
    where r.Level < 3
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score, 1) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score, 1) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore,
        case 
            when p.Score > 0 then 'Positive'
            when p.Score = 0 then 'Neutral'
            else 'Negative'
        end as ScoreCategory
    from Posts p
    where p.PostTypeId in (1, 2)
),
PostCloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
),
UserCommentActivity as (
    select
        c.UserId,
        count(distinct c.PostId) as DistinctPostsCommented,
        count(*) as TotalComments,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct substring(c.Text from 1 for 30), ' | ') as SampleComments
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
AnswerWithAcceptedFlag as (
    select
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.Score,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
),
UserAnswerStats as (
    select
        a.OwnerUserId,
        count(*) as TotalAnswers,
        sum(a.IsAccepted) as AcceptedAnswers,
        avg(a.Score) as AvgAnswerScore,
        count(distinct unnest(string_to_array(substring(a.QuestionTags, 2, length(a.QuestionTags)-2), '><'))) as DistinctTagsAnswered
    from AnswerWithAcceptedFlag a
    group by a.OwnerUserId
),
CombinedUserStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ubs.GoldBadges, 0) as GoldBadges,
        coalesce(ubs.SilverBadges, 0) as SilverBadges,
        coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
        coalesce(ubs.TagBasedBadges, 0) as TagBasedBadges,
        coalesce(uas.TotalAnswers, 0) as TotalAnswers,
        coalesce(uas.AcceptedAnswers, 0) as AcceptedAnswers,
        coalesce(uas.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(uas.DistinctTagsAnswered, 0) as DistinctTagsAnswered,
        coalesce(uca.DistinctPostsCommented, 0) as DistinctPostsCommented,
        coalesce(uca.TotalComments, 0) as TotalComments,
        uca.LastCommentDate,
        ubs.LastBadgeDate
    from Users u
    left join UserBadgeSummary ubs on ubs.UserId = u.Id
    left join UserAnswerStats uas on uas.OwnerUserId = u.Id
    left join UserCommentActivity uca on uca.UserId = u.Id
)
select
    cus.Id as UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.CreationDate,
    cus.LastAccessDate,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.TagBasedBadges,
    cus.TotalAnswers,
    cus.AcceptedAnswers,
    round(cus.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    cus.DistinctTagsAnswered,
    cus.DistinctPostsCommented,
    cus.TotalComments,
    cus.LastCommentDate,
    cus.LastBadgeDate,
    rth.Level as TagHierarchyLevel,
    rth.Path as TagHierarchyPath,
    coalesce(pcrc.CloseCount, 0) as TotalCloseVotes,
    coalesce(pcrc.CloseReasonName, 'No Close Reason') as MostCommonCloseReason,
    case
        when cus.Reputation > 10000 then 'High Rep'
        when cus.Reputation between 1000 and 10000 then 'Medium Rep'
        else 'Low Rep'
    end as ReputationCategory,
    case
        when cus.TotalAnswers > 0 then round((cus.AcceptedAnswers::numeric / cus.TotalAnswers) * 100, 2)
        else null
    end as AcceptedAnswerPercentage,
    case
        when cus.TotalComments > 0 then round((cus.DistinctPostsCommented::numeric / cus.TotalComments) * 100, 2)
        else null
    end as CommentSpreadPercentage,
    concat_ws(' | ',
        substring(cus.DisplayName from 1 for 10),
        'Rep: ' || cus.Reputation,
        'Badges: G' || cus.GoldBadges || ' S' || cus.SilverBadges || ' B' || cus.BronzeBadges,
        'Answers: ' || cus.TotalAnswers,
        'Accepted %: ' || coalesce(round((cus.AcceptedAnswers::numeric / nullif(cus.TotalAnswers,0)) * 100,2)::text, 'N/A'),
        'Comments: ' || cus.TotalComments
    ) as UserSummary
from CombinedUserStats cus
left join RecursiveTagHierarchy rth on rth.Level = 1
left join (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        sum(1) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
    order by CloseCount desc
    limit 1
) pcrc on pcrc.PostId = (
    select p.Id from Posts p where p.OwnerUserId = cus.Id order by p.ViewCount desc limit 1
)
where cus.Reputation > 500
order by cus.Reputation desc, cus.TotalAnswers desc
limit 50;