-- {"query": "437.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1991} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    left join Users u on p.OwnerUserId = u.Id
    where p.CreationDate >= current_date - interval '365 days'
),
TopPostsPerTag as (
    select
        Id,
        TagName,
        PostId,
        Score,
        ViewCount,
        CreationDate,
        OwnerUserId,
        DisplayName
    from RecursiveTagCounts
    where rn <= 5
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
PostVoteStats as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        count(v.Id) as TotalVotes
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id
),
ClosedQuestions as (
    select
        ph.PostId,
        min(ph.CreationDate) as ClosedDate,
        crt.Name as CloseReason
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on ph.Comment::int = crt.Id
    group by ph.PostId, crt.Name
),
AnswerStats as (
    select
        q.Id as QuestionId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
RankedQuestions as (
    select
        q.Id,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.OwnerUserId,
        u.DisplayName,
        av.UpVotes,
        av.DownVotes,
        av.Favorites,
        av.TotalVotes,
        cs.ClosedDate,
        cs.CloseReason,
        ans.AnswerCount,
        ans.AvgAnswerScore,
        ans.MaxAnswerScore,
        ans.AnonymousAnswers,
        row_number() over (partition by q.OwnerUserId order by q.Score desc, q.ViewCount desc) as UserQuestionRank
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join PostVoteStats av on q.Id = av.PostId
    left join ClosedQuestions cs on q.Id = cs.PostId
    left join AnswerStats ans on q.Id = ans.QuestionId
    where q.PostTypeId = 1
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct q.Id) as TotalQuestions,
        count(distinct a.Id) as TotalAnswers,
        coalesce(sum(vs.UpVotes),0) as TotalUpVotesReceived,
        coalesce(sum(vs.DownVotes),0) as TotalDownVotesReceived,
        coalesce(sum(bc.GoldBadges),0) as GoldBadges,
        coalesce(sum(bc.SilverBadges),0) as SilverBadges,
        coalesce(sum(bc.BronzeBadges),0) as BronzeBadges,
        max(bc.LastBadgeDate) as LastBadgeDate,
        max(p.LastActivityDate) as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join PostVoteStats vs on vs.PostId = p.Id
    left join UserBadgeCounts bc on bc.UserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as OwnerDisplayName,
        p.Title as PostTitle,
        rp.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
    join Posts p on pl.PostId = p.Id
    join Posts rp on pl.RelatedPostId = rp.Id
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
),
ComplexQuestionAnalysis as (
    select
        rq.Id,
        rq.Title,
        rq.Score,
        rq.ViewCount,
        rq.CreationDate,
        rq.DisplayName as Owner,
        rq.UpVotes,
        rq.DownVotes,
        rq.Favorites,
        rq.TotalVotes,
        rq.ClosedDate,
        rq.CloseReason,
        rq.AnswerCount,
        rq.AvgAnswerScore,
        rq.MaxAnswerScore,
        rq.AnonymousAnswers,
        case
            when rq.ClosedDate is not null then 'Closed'
            when rq.AnswerCount = 0 then 'Unanswered'
            when rq.Score > 10 and rq.AnswerCount > 5 then 'Popular'
            else 'Normal'
        end as QuestionStatus,
        string_agg(distinct dt.RelatedPostTitle, '; ') filter (where dt.RelatedPostTitle is not null) as DuplicateTitles,
        ua.TotalPosts,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.TotalUpVotesReceived,
        ua.TotalDownVotesReceived,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.LastBadgeDate,
        ua.LastActivityDate
    from RankedQuestions rq
    left join DuplicateLinks dt on dt.PostId = rq.Id
    left join UserActivitySummary ua on ua.Id = rq.OwnerUserId
    group by
        rq.Id, rq.Title, rq.Score, rq.ViewCount, rq.CreationDate, rq.DisplayName,
        rq.UpVotes, rq.DownVotes, rq.Favorites, rq.TotalVotes, rq.ClosedDate, rq.CloseReason,
        rq.AnswerCount, rq.AvgAnswerScore, rq.MaxAnswerScore, rq.AnonymousAnswers,
        ua.TotalPosts, ua.TotalQuestions, ua.TotalAnswers, ua.TotalUpVotesReceived,
        ua.TotalDownVotesReceived, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges,
        ua.LastBadgeDate, ua.LastActivityDate
)
select
    cqa.Id as QuestionId,
    cqa.Title,
    cqa.Owner,
    cqa.CreationDate,
    cqa.Score,
    cqa.ViewCount,
    cqa.UpVotes,
    cqa.DownVotes,
    cqa.Favorites,
    cqa.TotalVotes,
    cqa.QuestionStatus,
    coalesce(cqa.CloseReason, 'N/A') as CloseReason,
    cqa.AnswerCount,
    round(coalesce(cqa.AvgAnswerScore,0),2) as AvgAnswerScore,
    cqa.MaxAnswerScore,
    cqa.AnonymousAnswers,
    coalesce(cqa.DuplicateTitles, 'None') as DuplicateQuestionTitles,
    cqa.TotalPosts,
    cqa.TotalQuestions,
    cqa.TotalAnswers,
    cqa.TotalUpVotesReceived,
    cqa.TotalDownVotesReceived,
    cqa.GoldBadges,
    cqa.SilverBadges,
    cqa.BronzeBadges,
    cqa.LastBadgeDate,
    cqa.LastActivityDate,
    length(cqa.Title) as TitleLength,
    case when cqa.ViewCount > 0 then round(cqa.Score::numeric / cqa.ViewCount, 4) else null end as ScorePerView,
    case when cqa.AnswerCount > 0 then round(cqa.MaxAnswerScore::numeric / cqa.AnswerCount, 4) else null end as MaxAnswerScorePerAnswer
from ComplexQuestionAnalysis cqa
where cqa.CreationDate >= current_date - interval '90 days'
order by cqa.Score desc, cqa.ViewCount desc
limit 100;