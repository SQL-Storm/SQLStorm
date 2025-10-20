with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        coalesce(u.Reputation, 0) as TopUserReputation,
        row_number() over (partition by t.Id order by coalesce(u.Reputation, 0) desc) as rn
    from
        Tags t
        left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
        left join Users u on u.Id = (
            select p2.OwnerUserId
            from Posts p2
            where p2.Tags like '%' || '<' || t.TagName || '>' || '%'
            order by p2.OwnerUserId desc
            limit 1
        )
),
UserBadgeCounts as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostScoreStats as (
    select
        p.OwnerUserId,
        avg(p.Score) as AvgScore,
        max(p.Score) as MaxScore,
        min(p.Score) as MinScore,
        count(*) as PostCount
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(bc.GoldBadges, 0) as GoldBadges,
        coalesce(bc.SilverBadges, 0) as SilverBadges,
        coalesce(bc.BronzeBadges, 0) as BronzeBadges,
        coalesce(ps.AvgScore, 0) as AvgPostScore,
        coalesce(ps.MaxScore, 0) as MaxPostScore,
        coalesce(ps.MinScore, 0) as MinPostScore,
        coalesce(ps.PostCount, 0) as PostCount,
        rank() over (order by u.Reputation desc, ps.MaxScore desc) as ReputationRank
    from Users u
    left join UserBadgeCounts bc on bc.UserId = u.Id
    left join PostScoreStats ps on ps.OwnerUserId = u.Id
),
RecentPostComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - interval '30 days')
    group by c.PostId
),
PostsWithVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        rpc.CommentCount,
        rpc.LastCommentDate
    from Posts p
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    left join RecentPostComments rpc on rpc.PostId = p.Id
),
DuplicatePostLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
UserAnswerRanks as (
    select
        p.OwnerUserId,
        p.ParentId as QuestionId,
        p.Id as AnswerId,
        rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2 and p.OwnerUserId is not null
),
TopAnswers as (
    select
        uar.QuestionId,
        uar.AnswerId,
        uar.OwnerUserId,
        uar.AnswerRank
    from UserAnswerRanks uar
    where uar.AnswerRank = 1
),
QuestionAnswerDetails as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.OwnerUserId as QuestionOwnerId,
        ta.AnswerId as TopAnswerId,
        ta.OwnerUserId as TopAnswerOwnerId
    from Posts q
    left join TopAnswers ta on ta.QuestionId = q.Id
    where q.PostTypeId = 1
),
ComplexUserStats as (
    select
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.AvgPostScore,
        ua.MaxPostScore,
        ua.MinPostScore,
        ua.PostCount,
        count(distinct qad.QuestionId) filter (where qad.TopAnswerOwnerId = ua.Id) as TopAnswerCount,
        sum(case when qad.QuestionScore > 10 then 1 else 0 end) as HighScoreQuestions,
        sum(case when qad.QuestionViews > 1000 then 1 else 0 end) as PopularQuestions
    from UserActivity ua
    left join QuestionAnswerDetails qad on (qad.QuestionOwnerId = ua.Id or qad.TopAnswerOwnerId = ua.Id)
    group by ua.Id, ua.DisplayName, ua.Reputation, ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges, ua.AvgPostScore, ua.MaxPostScore, ua.MinPostScore, ua.PostCount
),
FinalResult as (
    select
        c.Id as UserId,
        c.DisplayName,
        c.Reputation,
        c.GoldBadges,
        c.SilverBadges,
        c.BronzeBadges,
        c.AvgPostScore,
        c.MaxPostScore,
        c.MinPostScore,
        c.PostCount,
        c.TopAnswerCount,
        c.HighScoreQuestions,
        c.PopularQuestions,
        (
            select array_agg(tn) from (
                select t2.TagName as tn, t2.Count as cnt
                from Tags t2
                where exists (
                    select 1
                    from Posts pwv_sub
                    where pwv_sub.OwnerUserId = c.Id
                      and pwv_sub.Tags like '%' || '<' || t2.TagName || '>' || '%'
                )
                  and t2.Count > 1000
                order by t2.Count desc
            ) s
        ) as PopularTags,
        coalesce(pwv.UpVotes, 0) as TotalUpVotesOnPosts,
        coalesce(pwv.DownVotes, 0) as TotalDownVotesOnPosts,
        coalesce(pwv.CommentCount, 0) as RecentCommentsCount
    from ComplexUserStats c
    left join PostsWithVotes pwv on pwv.OwnerUserId = c.Id
    group by c.Id, c.DisplayName, c.Reputation, c.GoldBadges, c.SilverBadges, c.BronzeBadges, c.AvgPostScore, c.MaxPostScore, c.MinPostScore, c.PostCount, c.TopAnswerCount, c.HighScoreQuestions, c.PopularQuestions, pwv.UpVotes, pwv.DownVotes, pwv.CommentCount
    having c.PostCount > 10 and c.Reputation > 1000
)
select
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.AvgPostScore,
    fr.MaxPostScore,
    fr.MinPostScore,
    fr.PostCount,
    fr.TopAnswerCount,
    fr.HighScoreQuestions,
    fr.PopularQuestions,
    coalesce(string_agg(distinct t.pt, ', '), 'None') as TopTags,
    fr.TotalUpVotesOnPosts,
    fr.TotalDownVotesOnPosts,
    fr.RecentCommentsCount,
    case
        when fr.Reputation > 50000 then 'Legend'
        when fr.Reputation > 20000 then 'Expert'
        when fr.Reputation > 5000 then 'Intermediate'
        else 'Beginner'
    end as UserLevel
from FinalResult fr
left join lateral (
    select unnest(fr.PopularTags) as pt
    order by 1
    limit 5
) t on true
group by fr.UserId, fr.DisplayName, fr.Reputation, fr.GoldBadges, fr.SilverBadges, fr.BronzeBadges, fr.AvgPostScore, fr.MaxPostScore, fr.MinPostScore, fr.PostCount, fr.TopAnswerCount, fr.HighScoreQuestions, fr.PopularQuestions, fr.TotalUpVotesOnPosts, fr.TotalDownVotesOnPosts, fr.RecentCommentsCount
order by fr.Reputation desc, fr.TopAnswerCount desc
limit 50;