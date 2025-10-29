-- {"query": "2986.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1990} 
with RecursivePostVotes as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    left join (
        select PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on p.Id = v.PostId
    where p.PostTypeId in (1,2)
),
UserBadgeCount as (
    select 
        UserId,
        sum(case when Class=1 then 1 else 0 end) as GoldBadges,
        sum(case when Class=2 then 1 else 0 end) as SilverBadges,
        sum(case when Class=3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
),
UserSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        avg(nullif(p.Score,0)) filter (where p.Score is not null) as AvgPostScore,
        max(p.Score) as MaxPostScore
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join UserBadgeCount b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, b.GoldBadges, b.SilverBadges, b.BronzeBadges
),
RankedQuestions as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as RankForUser,
        count(c.Id) as CommentCount,
        bool_or(v.VoteTypeId = 6) as IsClosedVoteExists,  -- close vote exists in Votes table (rare, closure mostly in PostHistory)
        exists (
            select 1 from PostHistory ph
            where ph.PostId = p.Id and ph.PostHistoryTypeId = 10
        ) as IsClosedPost
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id and v.VoteTypeId = 6
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.AcceptedAnswerId
),
DuplicateLinks as (
    select
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId,
        p1.Tags as DuplicateTags,
        p2.Tags as OriginalTags,
        p1.CreationDate as DuplicateCreated,
        p2.CreationDate as OriginalCreated
    from PostLinks pl
    join Posts p1 on pl.PostId = p1.Id and p1.PostTypeId = 1
    join Posts p2 on pl.RelatedPostId = p2.Id and p2.PostTypeId = 1
    where pl.LinkTypeId = 3 -- duplicate
),
FilteredTags as (
    select 
        t.TagName,
        t.Count,
        substring(t.TagName from '^[a-z]+') as TagPrefix,
        length(t.TagName) as TagLength,
        coalesce(p.Score, 0) as RelatedPostScore
    from Tags t
    left join Posts p on t.ExcerptPostId = p.Id
    where t.Count > 1000
),
AggregatedUserEngagement as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(p.CommentCount) as TotalComments,
        sum(p.FavoriteCount) as TotalFavorites,
        max(p.Score) as HighestScore,
        avg(p.Score) as AvgScore,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.UserId = u.Id
    group by u.Id, u.DisplayName
),
CorrelatedAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.AcceptedAnswerId,
        coalesce(a.TotalAnswers, 0) as TotalAnswers,
        coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore
    from Posts q
    left join (
      select 
          ParentId,
          count(*) as TotalAnswers,
          avg(Score) as AvgAnswerScore,
          max(Score) as MaxAnswerScore
      from Posts
      where PostTypeId = 2
      group by ParentId
    ) a on q.Id = a.ParentId
    where q.PostTypeId = 1
),
FinalResult as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgPostScore,
        us.MaxPostScore,
        ab.GoldBadges,
        ab.SilverBadges,
        ab.BronzeBadges,
        q.Id as TopQuestionId,
        q.Title as TopQuestionTitle,
        q.Score as TopQuestionScore,
        q.ViewCount as TopQuestionViews,
        q.AcceptedAnswerId,
        q.Tags as QuestionTags,
        coalesce(ans.TotalAnswers,0) as TotalAnswersToTopQuestion,
        coalesce(ans.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
        dl.DuplicatePostId,
        dl.OriginalPostId,
        dl.DuplicateCreated,
        dl.OriginalCreated,
        dt.TagName,
        dt.Count as TagPopularity,
        dt.TagPrefix,
        dt.TagLength,
        e.TotalPosts as UserTotalPosts,
        e.TotalComments as UserTotalComments,
        e.TotalFavorites as UserTotalFavorites,
        e.CloseEvents,
        e.ReopenEvents
    from Users u
    join UserSummary us on u.Id = us.UserId
    left join UserBadgeCount ab on u.Id = ab.UserId
    left join LATERAL (
        select q1.*
        from RankedQuestions q1
        where q1.OwnerUserId = u.Id and q1.RankForUser = 1
        limit 1
    ) q on true
    left join CorrelatedAnswerStats ans on q.Id = ans.QuestionId
    left join DuplicateLinks dl on dl.DuplicatePostId = q.Id
    left join FilteredTags dt on dt.TagName = any(string_to_array(coalesce(q.Tags,''),'><'))
    left join AggregatedUserEngagement e on e.Id = u.Id
    where u.Reputation > 1000
)
select 
    UserId,
    DisplayName,
    Reputation,
    UserCreationDate,
    QuestionCount,
    AnswerCount,
    coalesce(AvgPostScore,0)::numeric(10,2) as AvgPostScore,
    MaxPostScore,
    coalesce(GoldBadges,0) as GoldBadges,
    coalesce(SilverBadges,0) as SilverBadges,
    coalesce(BronzeBadges,0) as BronzeBadges,
    TopQuestionId,
    left(TopQuestionTitle, 100) as TopQuestionTitleSnippet,
    TopQuestionScore,
    TopQuestionViews,
    AcceptedAnswerId,
    QuestionTags,
    TotalAnswersToTopQuestion,
    coalesce(AvgAnswerScore,0)::numeric(10,2) as AvgAnswerScore,
    MaxAnswerScore,
    DuplicatePostId,
    OriginalPostId,
    DuplicateCreated,
    OriginalCreated,
    TagName,
    TagPopularity,
    TagPrefix,
    TagLength,
    UserTotalPosts,
    UserTotalComments,
    UserTotalFavorites,
    CloseEvents,
    ReopenEvents
from FinalResult
order by Reputation desc, TopQuestionScore desc, UserTotalPosts desc
limit 100;