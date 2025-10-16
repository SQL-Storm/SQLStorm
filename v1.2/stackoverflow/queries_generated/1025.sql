-- {"query": "1025.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1732} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired, 0 as Level,
           array[t.TagName] as TagPath
    from Tags t
    where t.IsRequired = 1
    union all
    select c.Id, c.TagName, c.Count, c.IsModeratorOnly, c.IsRequired, r.Level + 1,
           r.TagPath || c.TagName
    from Tags c
    join PostLinks pl on pl.PostId = c.ExcerptPostId
    join Posts p on p.Id = pl.RelatedPostId
    join RecursiveTagHierarchy r on p.Tags like '%' || r.TagName || '%'
    where c.IsRequired = 0 and c.Id != r.Id
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        count(*) over (partition by p.OwnerUserId) as TotalPosts,
        sum(case when p.Score > 10 then 1 else 0 end) over (partition by p.OwnerUserId) as HighScorePosts,
        max(p.Score) over (partition by p.OwnerUserId) as MaxScore
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2) -- Question or Answer
),
AcceptedAnswers as (
    select 
        q.Id as QuestionId, 
        a.Id as AnswerId, 
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts q
    join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
CommentsSummary as (
    select
        c.PostId,
        count(*) as TotalComments,
        sum(case when c.Score >= 5 then 1 else 0 end) as HighScoreComments,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, '[anonymous]'), ', ') as Commenters
    from Comments c
    group by c.PostId
),
BadgeSummary as (
    select
        b.UserId,
        count(*) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
PostHistoriesFlagged as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 else null end) as CloseVotes,
        count(case when ph.PostHistoryTypeId = 12 then 1 else null end) as Deletions,
        count(case when ph.PostHistoryTypeId = 25 then 1 else null end) as Tweets,
        max(ph.CreationDate) as LastHistoryDate,
        array_agg(distinct ph.Comment) filter (where ph.Comment is not null) as CloseReasons
    from PostHistory ph
    group by ph.PostId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        rank() over (order by u.Reputation desc) as ReputationRank,
        rank() over (order by u.LastAccessDate desc) as RecentActiveRank
    from Users u
),
Combined as (
    select 
        r.PostTypeId,
        r.Id as PostId,
        r.CreationDate as PostCreation,
        r.Score as PostScore,
        r.ViewCount,
        r.Tags,
        r.OwnerUserId,
        r.OwnerName,
        r.RecentPostRank,
        r.TotalPosts,
        r.HighScorePosts,
        r.MaxScore,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerCreationDate,
        c.TotalComments,
        c.HighScoreComments,
        c.LastCommentDate,
        c.Commenters,
        b.BadgeCount,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        b.HasTagBasedBadge,
        phf.CloseVotes,
        phf.Deletions,
        phf.Tweets,
        phf.LastHistoryDate,
        phf.CloseReasons,
        ua.Reputation,
        ua.ReputationRank,
        ua.RecentActiveRank
    from RankedPosts r
    left join AcceptedAnswers a on a.QuestionId = r.Id
    left join CommentsSummary c on c.PostId = r.Id
    left join BadgeSummary b on b.UserId = r.OwnerUserId
    left join PostHistoriesFlagged phf on phf.PostId = r.Id
    left join UserActivity ua on ua.Id = r.OwnerUserId
    where r.TotalPosts > 10
),
FilteredCombined as (
    select *
    from Combined
    where
        (PostTypeId = 1 and Score > 5 and (HighScorePosts > 2 or BadgeCount > 5))
        or
        (PostTypeId = 2 and AnswerScore >= 10 and TotalComments > 3)
),
OrderedResults as (
    select
        *,
        dense_rank() over (order by PostScore desc, ViewCount desc, BadgeCount desc nulls last) as PRank,
        dense_rank() over (partition by OwnerUserId order by CreationDate desc) as OwnerPostRankDesc
    from FilteredCombined
)
select
    PRank,
    PostId,
    case when PostTypeId = 1 then 'Question' else 'Answer' end as PostType,
    coalesce(substr(OwnerName, 1, 20), '[deleted]') as OwnerNameShort,
    PostCreation,
    PostScore,
    ViewCount,
    coalesce(Tags, '') as TagsSnippet,
    TotalComments,
    HighScoreComments,
    coalesce(Commenters, '') as CommentersList,
    BadgeCount,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    coalesce(array_to_string(CloseReasons, ', '), 'None') CloseReasons,
    Reputation,
    ReputationRank,
    RecentActiveRank,
    case 
        when CloseVotes > 0 then 'Recently flagged for close'
        when Deletions > 0 then 'Recently deleted'
        else 'Active'
    end as PostStatus,
    AnswerId,
    AnswerScore,
    AnswerCreationDate,
    OwnerPostRankDesc,
    -- Complex string expression: first 3 tags suffix joined by '|'
    regexp_replace(
        array_to_string(
            (regexp_split_to_array(coalesce(Tags, ''), '><'))[1:3], 
            '|'),
        '[^[:alnum:]|]+', '_', 'g'
    ) as TagCode,
    -- Numeric expression mixing window function and logic
    (PostScore * 1.0 / nullif(HighScorePosts,0)) * (1 + BadgeCount * 0.1) as WeightedImpact,
    -- Complex NULL logic with coalesce and case
    coalesce(nullif(Location, ''), 'Unknown') as UserLocation,
    -- Outer join simulation: Subquery to get last post history text
    (
        select ph.Text
        from PostHistory ph
        where ph.PostId = OrderedResults.PostId
        order by ph.CreationDate desc limit 1
    ) as LastPostHistoryText
from OrderedResults
where PRank <= 100
order by PRank, PostScore desc, ViewCount desc
limit 100;