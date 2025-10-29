with RecursiveTagCounts as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagAggregates as (
    select
        Tag,
        count(*) as QuestionCount,
        avg(Score) as AvgQuestionScore,
        sum(ViewCount) as TotalViews
    from RecursiveTagCounts
    group by Tag
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsAsked,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersGiven,
        coalesce(sum(vs.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vs.DownVotes),0) as TotalDownVotes,
        max(case when p.PostTypeId = 2 then p.Score end) as MaxAnswerScore,
        min(case when p.PostTypeId = 1 then p.Score end) as MinQuestionScore,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join lateral (
        select
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        where v.PostId = p.Id
    ) vs on true
    group by u.Id, u.DisplayName, u.Reputation
),
PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.CreationDate,
        p.AcceptedAnswerId,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        c.Name as PostTypeName,
        (select count(1)
            from Comments cm
            where cm.PostId = p.Id and cm.Score > 0
        ) as PositiveCommentCount,
        (select count(1)
            from PostHistory ph
            where ph.PostId = p.Id and ph.PostHistoryTypeId = 10
        ) as TimesClosed,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserPostRankByDate
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join PostTypes c on c.Id = p.PostTypeId
),
HighImpactPosts as (
    select
        pd.*
    from PostDetails pd
    where pd.Score > (
        select percentile_cont(0.9) within group (order by Score)
        from Posts 
        where PostTypeId = pd.PostTypeId
    )
      and pd.PositiveCommentCount > 5
      and pd.TimesClosed = 0
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        lt.Name as LinkTypeName
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
MergedBadges as (
    select
        b.UserId,
        count(*) as BadgeCount,
        string_agg(distinct b.Name, ', ') as BadgeNames,
        max(b.Class) as HighestClass
    from Badges b
    group by b.UserId
),
AnswerRanking as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        u.Id as AnswererId,
        u.DisplayName,
        rank() over (partition by a.ParentId order by a.Score desc) as AnswerRank,
        count(*) over (partition by a.ParentId) as TotalAnswers,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
TopAnsweredQuestions AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        a.TotalAnswers,
        a.AnswerId as TopAnswerId,
        a.AnswererId as TopAnswererId,
        a.DisplayName as TopAnswererName,
        a.Score as TopAnswerScore,
        a.IsAccepted
    from Posts q
    join (
        select distinct on (QuestionId) AnswerId, QuestionId, Score, AnswererId, DisplayName, AnswerRank, TotalAnswers, IsAccepted
        from AnswerRanking
        order by QuestionId, AnswerRank
    ) a on a.QuestionId = q.Id
    where q.PostTypeId = 1
      and q.CreationDate > (cast('2024-10-01' as date) - interval '180 day')
),
TagUserParticipation AS (
    select 
        rtc.Tag,
        up.UserId,
        us.DisplayName,
        count(*) as PostsInTag
    from RecursiveTagCounts rtc
    join Posts p on p.Id = rtc.PostId
    join Users us on us.Id = p.OwnerUserId
    join UserPostStats up on up.UserId = us.Id
    group by rtc.Tag, up.UserId, us.DisplayName
    having count(*) > 5
),
FullTextSearchBodies AS (
    select
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        -- use a neutral expression for full-text rank: avoid dialect-specific to_tsvector/plainto_tsquery calls
        -- compute a simple fallback relevance score using POSITION and LENGTH to approximate keyword matches
        (
          (case when position('performance' in coalesce(p.Body,'')) > 0 then 1 else 0 end)
          + (case when position('optimization' in coalesce(p.Body,'')) > 0 then 1 else 0 end)
        )::integer as Rank
    from Posts p
    where p.PostTypeId in (1,2)
),
PostsWithBadges AS (
    select
        p.Id as PostId,
        p.Title,
        p.Score,
        b.BadgeCount,
        b.BadgeNames,
        b.HighestClass
    from Posts p
    left join MergedBadges b on p.OwnerUserId = b.UserId
    where p.PostTypeId = 1
)
select 
    q.Title as QuestionTitle,
    q.Score as QuestionScore,
    q.ViewCount,
    q.TotalAnswers,
    q.TopAnswerScore,
    q.TopAnswererName,
    tagAgg.QuestionCount,
    tagAgg.AvgQuestionScore,
    tagAgg.TotalViews as TagTotalViews,
    up.QuestionsAsked,
    up.AnswersGiven,
    up.TotalUpVotes,
    up.TotalDownVotes,
    up.MaxAnswerScore,
    up.MinQuestionScore,
    up.ReputationRank,
    dup.LinkTypeName as DuplicateLinkType,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateRelatedPostTitle,
    ph.UserPostRankByDate,
    tsb.Rank as FullTextSearchRank,
    pb.BadgeCount,
    pb.BadgeNames,
    pb.HighestClass
from TopAnsweredQuestions q
left join TagAggregates tagAgg on tagAgg.Tag = (
    select t.TagName
    from Tags t
    where t.Count = (
        select max(t2.Count) from Tags t2 where t2.TagName = split_part(q.Title, ' ', 1)
        limit 1
    )
    limit 1
)
left join UserPostStats up on up.UserId = (
    select p2.OwnerUserId from Posts p2 where p2.Id = q.QuestionId
)
left join DuplicateLinks dup on dup.PostId = q.QuestionId
left join PostDetails ph on ph.Id = q.QuestionId
left join FullTextSearchBodies tsb on tsb.Id = q.QuestionId
left join PostsWithBadges pb on pb.PostId = q.QuestionId
where q.Score > 10
order by q.Score desc, q.ViewCount desc
limit 50;