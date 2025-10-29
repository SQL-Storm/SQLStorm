-- {"query": "2978.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2303} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on
        t2.Id <> all(r.Path) and
        strpos(' ' || coalesce(t2.TagName, '') || ' ', ' ' || coalesce((select TagName from Tags where Id = r.Id), '') || ' ') > 0
        and r.Level < 3
),
UserQStats as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionsAsked,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        count(*) filter (where p.PostTypeId = 2) as AnswersProvided,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
LatestPostEdits as (
    select ph.PostId, max(ph.CreationDate) as LastEdit
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6,7,8,9)
    group by ph.PostId
),
PostsWithCloseInfo as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        p.OwnerUserId,
        lpe.LastEdit,
        close.ReasonName,
        close.ClosedDate
    from Posts p
    left join LatestPostEdits lpe on lpe.PostId = p.Id
    left join (
        select ph.PostId, crt.Name as ReasonName, min(ph.CreationDate) as ClosedDate
        from PostHistory ph
        join CloseReasonTypes crt on crt.Id::int = nullif(ph.Comment, '')::int
        where ph.PostHistoryTypeId = 10
        group by ph.PostId, crt.Name
    ) close on close.PostId = p.Id
),
UserCommentActivity AS (
    select
        c.UserId,
        count(*) as CommentsMade,
        avg(c.Score) as AvgCommentScore,
        bool_or(c.Text ilike '%help%') as HasHelpMentions
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
AnswerScoresWindow AS (
    select
        p.ParentId as QuestionId,
        p.Id as AnswerId,
        p.OwnerUserId,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank,
        rank() over (partition by p.ParentId order by p.Score desc) as ScoreRank,
        count(*) over (partition by p.ParentId) as TotalAnswers
    from Posts p
    where p.PostTypeId = 2
),
TopAnswers AS (
    select *
    from AnswerScoresWindow
    where AnswerRank <= 3
),
UserLinkDups AS (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        u.Id as UserId,
        u.DisplayName
    from PostLinks pl
    left join Posts p on p.Id = pl.PostId
    left join Users u on u.Id = p.OwnerUserId
),
QuestionTags AS (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as TagName
    from Posts p
    where p.Tags is not null and p.PostTypeId = 1
),
QuestionsWithTagCounts AS (
    select
        q.PostId,
        count(distinct qt.TagName) as NumTags
    from Posts q
    left join QuestionTags qt on qt.PostId = q.Id
    where q.PostTypeId = 1
    group by q.PostId
),
AggregatedActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(uqs.QuestionsAsked,0) as QuestionsAsked,
        coalesce(uqs.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(uqs.AnswersProvided,0) as AnswersProvided,
        coalesce(uqs.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(uqs.TotalQuestionViews,0) as TotalQuestionViews,
        coalesce(ubr.Gold, 0) as GoldBadges,
        coalesce(ubr.Silver, 0) as SilverBadges,
        coalesce(ubr.Bronze, 0) as BronzeBadges,
        coalesce(uca.CommentsMade,0) as CommentsMade,
        coalesce(uca.AvgCommentScore,0) as AvgCommentScore,
        u.Location,
        u.WebsiteUrl
    from Users u
    left join UserQStats uqs on uqs.OwnerUserId = u.Id
    left join (
        select UserId,
               max(case when Class = 1 then BadgeCount else 0 end) as Gold,
               max(case when Class = 2 then BadgeCount else 0 end) as Silver,
               max(case when Class = 3 then BadgeCount else 0 end) as Bronze
        from UserBadgeRanks
        group by UserId
    ) ubr on ubr.UserId = u.Id
    left join UserCommentActivity uca on uca.UserId = u.Id
),
FilteredTopUsers AS (
    select *
    from AggregatedActivity
    where Reputation > 10000 and QuestionsAsked >= 50
),
FinalQuestionAnswerStats AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AcceptedAnswerId,
        tq.NumTags,
        lpe.LastEdit,
        close.ReasonName,
        close.ClosedDate,
        json_agg(json_build_object(
            'AnswerId', ta.AnswerId,
            'OwnerUserId', ta.OwnerUserId,
            'Score', ta.Score,
            'AnswerRank', ta.AnswerRank
        ) order by ta.AnswerRank) filter (where ta.AnswerId is not null) as TopAnswers
    from Posts q
    left join QuestionsWithTagCounts tq on tq.PostId = q.Id
    left join LatestPostEdits lpe on lpe.PostId = q.Id
    left join (
        select ph.PostId, crt.Name as ReasonName, min(ph.CreationDate) as ClosedDate
        from PostHistory ph
        join CloseReasonTypes crt on crt.Id::int = nullif(ph.Comment, '')::int
        where ph.PostHistoryTypeId = 10
        group by ph.PostId, crt.Name
    ) close on close.PostId = q.Id
    left join TopAnswers ta on ta.QuestionId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Score, q.ViewCount, q.AcceptedAnswerId, tq.NumTags, lpe.LastEdit, close.ReasonName, close.ClosedDate
),
UserVoteAggregates AS (
    select
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesGiven,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesGiven,
        count(v.Id) as TotalVotesGiven
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId
)
select
    fqus.UserId,
    fqus.DisplayName,
    fqus.Reputation,
    fqus.QuestionsAsked,
    fqus.AvgQuestionScore,
    fqus.AnswersProvided,
    fqus.MaxAnswerScore,
    fqus.TotalQuestionViews,
    fqus.GoldBadges,
    fqus.SilverBadges,
    fqus.BronzeBadges,
    fqus.CommentsMade,
    fqus.AvgCommentScore,
    coalesce(votes.UpVotesGiven,0) as UpVotesGiven,
    coalesce(votes.DownVotesGiven,0) as DownVotesGiven,
    coalesce(votes.TotalVotesGiven,0) as TotalVotes,
    fqus.Location,
    fqus.WebsiteUrl,
    json_agg(json_build_object(
      'QuestionId', faqs.QuestionId,
      'Title', faqs.Title,
      'Score', faqs.QuestionScore,
      'ViewCount', faqs.ViewCount,
      'AcceptedAnswerId', faqs.AcceptedAnswerId,
      'TagCount', faqs.NumTags,
      'LastEdit', faqs.LastEdit,
      'CloseReason', faqs.ReasonName,
      'CloseDate', faqs.ClosedDate,
      'TopAnswers', faqs.TopAnswers
    ) order by faqs.Score desc) as TopQuestions
from FilteredTopUsers fqus
left join UserVoteAggregates votes on votes.UserId = fqus.UserId
left join Posts p on p.OwnerUserId = fqus.UserId and p.PostTypeId = 1
left join FinalQuestionAnswerStats faqs on faqs.QuestionId = p.Id
group by
    fqus.UserId,
    fqus.DisplayName,
    fqus.Reputation,
    fqus.QuestionsAsked,
    fqus.AvgQuestionScore,
    fqus.AnswersProvided,
    fqus.MaxAnswerScore,
    fqus.TotalQuestionViews,
    fqus.GoldBadges,
    fqus.SilverBadges,
    fqus.BronzeBadges,
    fqus.CommentsMade,
    fqus.AvgCommentScore,
    votes.UpVotesGiven,
    votes.DownVotesGiven,
    votes.TotalVotesGiven,
    fqus.Location,
    fqus.WebsiteUrl
having count(p.Id) >= 5
order by fqus.Reputation desc, fqus.QuestionsAsked desc
limit 50;